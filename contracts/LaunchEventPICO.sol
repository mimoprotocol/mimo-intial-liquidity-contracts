// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./interfaces/IMimoFactory.sol";
import "./interfaces/IMimoPair.sol";
import "./interfaces/IMimoV2Router02.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IVotingEscrow.sol";
import "./interfaces/IMasterChefPoint.sol";

/// @title Rocket Mimo Launch Event
/// @notice A liquidity launch contract enabling price discovery and token distribution at secondary market listing price
contract LaunchEventPICO is Ownable {
    using SafeERC20 for IERC20Metadata;

    /// @notice The phases the launch event can be in
    /// @dev Should these have more semantic names: Bid, Cancel, Withdraw
    enum Phase {
        NotStarted,
        PhaseOne,
        PhaseTwo,
        PhaseThree
    }

    struct UserInfo {
        /// @notice How much ETH user has deposited for this launch event
        uint256 balance;
        /// @notice Whether user has withdrawn the LP
        bool hasWithdrawnPair;
        /// @notice Whether user has withdrawn the issuing token incentives
        bool hasWithdrawnIncentives;
    }

    /// @notice Issuer of sale tokens
    address public issuer;

    /// @notice The start time of phase 1
    uint256 public auctionStart;

    uint256 public phaseOneDuration;
    uint256 public phaseOneNoFeeDuration;
    uint256 public phaseTwoDuration;

    /// @dev Amount of tokens used as incentives for locking up LPs during phase 3,
    /// in parts per 1e18 and expressed as an additional percentage to the tokens for auction.
    /// E.g. if tokenIncentivesPercent = 5e16 (5%), and issuer sends 105 000 tokens,
    /// then 105 000 * 5e16 / (1e18 + 5e16) = 5 000 tokens are used for incentives
    uint256 public tokenIncentivesPercent;

    /// @notice Floor price in ETH per token (can be 0)
    /// @dev floorPrice is scaled to 1e18
    uint256 public floorPrice;

    /// @notice Timelock duration post phase 3 when can user withdraw their LP tokens
    uint256 public userTimelock;

    /// @notice Timelock duration post phase 3 When can issuer withdraw their LP tokens
    uint256 public issuerTimelock;

    /// @notice The max withdraw penalty during phase 1, in parts per 1e18
    /// e.g. max penalty of 50% `maxWithdrawPenalty`= 5e17
    uint256 public maxWithdrawPenalty;

    /// @notice The fixed withdraw penalty during phase 2, in parts per 1e18
    /// e.g. fixed penalty of 20% `fixedWithdrawPenalty = 2e17`
    uint256 public fixedWithdrawPenalty;

    IWETH private WETH;
    IERC20Metadata public token;

    IMimoFactory public factory;
    IVotingEscrow public ve;
    IERC721 public machineFiNFT;

    bool public stopped;

    uint256 public maxAllocation;

    mapping(address => UserInfo) public getUserInfo;

    /// @dev The address of the MimoPair, set after createLiquidityPool is called
    IMimoPair public pair;

    /// @dev The total amount of eth that was sent to the router to create the initial liquidity pair.
    /// Used to calculate the amount of LP to send based on the user's participation in the launch event
    uint256 public ethAllocated;

    /// @dev The total amount of tokens that was sent to the router to create the initial liquidity pair.
    uint256 public tokenAllocated;

    /// @dev The exact supply of LP minted when creating the initial liquidity pair.
    uint256 private lpSupply;

    /// @dev Used to know how many issuing tokens will be sent to MimoRouter to create the initial
    /// liquidity pair. If floor price is not met, we will send fewer issuing tokens and `tokenReserve`
    /// will keep track of the leftover amount. It's then used to calculate the number of tokens needed
    /// to be sent to both issuer and users (if there are leftovers and every token is sent to the pair,
    /// tokenReserve will be equal to 0)
    uint256 private tokenReserve;

    /// @dev Keeps track of amount of token incentives that needs to be kept by contract in order to send the right
    /// amounts to issuer and users
    uint256 private tokenIncentivesBalance;
    /// @dev Total incentives for users for locking their LPs for an additional period of time after the pair is created
    uint256 private tokenIncentivesForUsers;
    /// @dev The share refunded to the issuer. Users receive 5% of the token that were sent to the Router.
    /// If the floor price is not met, the incentives still needs to be 5% of the value sent to the Router, so there
    /// will be an excess of tokens returned to the issuer if he calls `withdrawIncentives()`
    uint256 private tokenIncentiveIssuerRefund;

    /// @dev ethReserve is the exact amount of ETH that needs to be kept inside the contract in order to send everyone's
    /// ETH. If there is some excess (because someone sent token directly to the contract), the
    /// penaltyCollector can collect the excess using `skim()`
    uint256 private ethReserve;

    // TVL locker shares
    IMasterChefPoint public masterChefPoint;
    uint256 public pointShares;

    event LaunchEventInitialized(
        uint256 tokenIncentivesPercent,
        uint256 floorPrice,
        uint256 maxWithdrawPenalty,
        uint256 fixedWithdrawPenalty,
        uint256 maxAllocation,
        uint256 userTimelock,
        uint256 issuerTimelock,
        uint256 tokenReserve,
        uint256 tokenIncentives
    );

    event UserParticipated(
        address indexed user,
        uint256 ethAmount
    );

    event UserWithdrawn(
        address indexed user,
        uint256 ethAmount,
        uint256 penaltyAmount
    );

    event IncentiveTokenWithdraw(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    event LiquidityPoolCreated(
        address indexed pair,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1
    );

    event UserLiquidityWithdrawn(
        address indexed user,
        address indexed pair,
        uint256 amount
    );

    event IssuerLiquidityWithdrawn(
        address indexed issuer,
        address indexed pair,
        uint256 amount
    );

    event Stopped();

    event ETHEmergencyWithdraw(address indexed user, uint256 amount);

    event TokenEmergencyWithdraw(address indexed user, uint256 amount);

    /// @notice Modifier which ensures contract is in a defined phase
    modifier atPhase(Phase _phase) {
        _atPhase(_phase);
        _;
    }

    /// @notice Modifier which ensures the caller's timelock to withdraw has elapsed
    modifier timelockElapsed() {
        _timelockElapsed();
        _;
    }

    /// @notice Ensures launch event is stopped/running
    modifier isStopped(bool _stopped) {
        _isStopped(_stopped);
        _;
    }

    constructor(
        address _factory,
        address _weth,
        address _ve,
        address _machineFiNFT,
        uint256 _phaseOneDuration,
        uint256 _phaseOneNoFeeDuration,
        uint256 _phaseTwoDuration
    ) {
        factory = IMimoFactory(_factory);
        WETH = IWETH(_weth);
        ve = IVotingEscrow(_ve);
        machineFiNFT = IERC721(_machineFiNFT);
        phaseOneDuration = _phaseOneDuration;
        phaseOneNoFeeDuration = _phaseOneNoFeeDuration;
        phaseTwoDuration = _phaseTwoDuration;
    }

    /// @notice Initialize the launch event with needed parameters
    /// @param _issuer Address of the token issuer
    /// @param _auctionStart The start time of the auction
    /// @param _token The contract address of auctioned token
    /// @param _tokenIncentivesPercent The token incentives percent, in part per 1e18, e.g 5e16 is 5% of incentives
    /// @param _floorPrice The minimum price the token is sold at
    /// @param _maxWithdrawPenalty The max withdraw penalty during phase 1, in parts per 1e18
    /// @param _fixedWithdrawPenalty The fixed withdraw penalty during phase 2, in parts per 1e18
    /// @param _maxAllocation The maximum amount of ETH depositable per user
    /// @param _userTimelock The time a user must wait after auction ends to withdraw liquidity
    /// @param _issuerTimelock The time the issuer must wait after auction ends to withdraw liquidity
    /// @dev This function is called by the factory immediately after it creates the contract instance
    function initialize(
        address _issuer,
        uint256 _auctionStart,
        address _token,
        uint256 _tokenIncentivesPercent,
        uint256 _floorPrice,
        uint256 _maxWithdrawPenalty,
        uint256 _fixedWithdrawPenalty,
        uint256 _maxAllocation,
        uint256 _userTimelock,
        uint256 _issuerTimelock
    ) external onlyOwner atPhase(Phase.NotStarted) {
        require(auctionStart == 0, "already initialized");
        require(
            _token != address(WETH) && _token != address(0) &&
            _maxWithdrawPenalty <= 5e17 && _fixedWithdrawPenalty <= 5e17 && // 50%
            _userTimelock <= 7 days && _issuerTimelock > _userTimelock &&
            _auctionStart > block.timestamp && _issuer != address(0) &&
            _maxAllocation > 0 && _tokenIncentivesPercent < 1 ether,
            "parameters error"
        ); // 50%
        {
            address _pair = IMimoFactory(factory).getPair(_token, address(WETH));
            require(
                _pair == address(0) || IMimoPair(_pair).totalSupply() == 0,
                "liquid pair already exists"
            );
        }

        issuer = _issuer;

        auctionStart = _auctionStart;

        token = IERC20Metadata(_token);
        uint256 balance = token.balanceOf(address(this));

        tokenIncentivesPercent = _tokenIncentivesPercent;

        /// We do this math because `tokenIncentivesForUsers + tokenReserve = tokenSent`
        /// and `tokenIncentivesForUsers = tokenReserve * 0.05` (i.e. incentives are 5% of reserves for issuing).
        /// E.g. if issuer sends 105e18 tokens, `tokenReserve = 100e18` and `tokenIncentives = 5e18`
        tokenReserve = (balance * 1e18) / (1e18 + _tokenIncentivesPercent);
        require(tokenReserve > 0, "no token balance");
        tokenIncentivesForUsers = balance - tokenReserve;
        tokenIncentivesBalance = tokenIncentivesForUsers;

        floorPrice = _floorPrice;

        maxWithdrawPenalty = _maxWithdrawPenalty;
        fixedWithdrawPenalty = _fixedWithdrawPenalty;

        maxAllocation = _maxAllocation;

        userTimelock = _userTimelock;
        issuerTimelock = _issuerTimelock;

        emit LaunchEventInitialized(
            tokenIncentivesPercent,
            floorPrice,
            maxWithdrawPenalty,
            fixedWithdrawPenalty,
            maxAllocation,
            userTimelock,
            issuerTimelock,
            tokenReserve,
            tokenIncentivesBalance
        );
    }

    /// @notice The current phase the auction is in
    function currentPhase() public view returns (Phase) {
        if (auctionStart == 0 || block.timestamp < auctionStart) {
            return Phase.NotStarted;
        } else if (block.timestamp < auctionStart + phaseOneDuration) {
            return Phase.PhaseOne;
        } else if (
            block.timestamp < auctionStart + phaseOneDuration + phaseTwoDuration
        ) {
            return Phase.PhaseTwo;
        }
        return Phase.PhaseThree;
    }

    /// @notice Max allocation for user
    /// @param account The address of user
    function userMaxAllocation(address account) public view returns (uint256) {
        uint256 allocation = maxAllocation;
        uint256 count = machineFiNFT.balanceOf(account);
        if (count > 0) {
            allocation *= (5 * count);
        }
        if (pointShares > 0) {
            uint256 userPoints = masterChefPoint.userPoints(account);
            if (userPoints > 0) {
                allocation += maxAllocation * pointShares * userPoints / masterChefPoint.totalPoints();
            }
        }
        return allocation;
    }

    /// @notice Deposits ETH
    function depositETH()
        external
        payable
        isStopped(false)
        atPhase(Phase.PhaseOne)
    {
        require(msg.sender != issuer, "issuer cannot participate");
        require(
            msg.value > 0,
            "expected non-zero ETH to deposit"
        );

        UserInfo storage user = getUserInfo[msg.sender];
        uint256 newAllocation = user.balance + msg.value;

        require(
            newAllocation <= userMaxAllocation(msg.sender),
            "amount exceeds max allocation"
        );

        user.balance = newAllocation;
        ethReserve += msg.value;

        emit UserParticipated(msg.sender, msg.value);
    }

    /// @notice Withdraw ETH, only permitted during phase 1 and 2
    /// @param _amount The amount of ETH to withdraw
    function withdrawETH(uint256 _amount) external isStopped(false) {
        Phase _currentPhase = currentPhase();
        require(
            _currentPhase == Phase.PhaseOne || _currentPhase == Phase.PhaseTwo,
            "unable to withdraw"
        );
        require(_amount > 0, "invalid withdraw amount");
        UserInfo storage user = getUserInfo[msg.sender];
        require(
            user.balance >= _amount,
            "withdrawn amount exceeds balance"
        );
        user.balance -= _amount;

        uint256 feeAmount = (_amount * getPenalty()) / 1e18;
        uint256 amountMinusFee = _amount - feeAmount;

        ethReserve -= _amount;

        if (feeAmount > 0) {
            _safeTransferETH(owner(), feeAmount);
        }
        _safeTransferETH(msg.sender, amountMinusFee);
        emit UserWithdrawn(msg.sender, _amount, feeAmount);
    }

    /// @notice Create the MimoPair
    /// @dev Can only be called once after phase 3 has started
    function createPair() external isStopped(false) atPhase(Phase.PhaseThree) {
        (address wethAddress, address tokenAddress) = (
            address(WETH),
            address(token)
        );
        address _pair = factory.getPair(wethAddress, tokenAddress);
        require(
            _pair == address(0) || IMimoPair(_pair).totalSupply() == 0,
            "liquid pair already exists"
        );
        require(ethReserve > 0, "no eth balance");

        uint256 tokenDecimals = token.decimals();
        tokenAllocated = tokenReserve;

        // Adjust the amount of tokens sent to the pool if floor price not met
        if (floorPrice > (ethReserve * 10**tokenDecimals) / tokenAllocated) {
            tokenAllocated = (ethReserve * 10**tokenDecimals) / floorPrice;
            tokenIncentivesForUsers =
                (tokenIncentivesForUsers * tokenAllocated) /
                tokenReserve;
            tokenIncentiveIssuerRefund =
                tokenIncentivesBalance -
                tokenIncentivesForUsers;
        }

        ethAllocated = ethReserve;
        ethReserve = 0;

        tokenReserve -= tokenAllocated;

        WETH.deposit{value: ethAllocated}();
        if (_pair == address(0)) {
            pair = IMimoPair(factory.createPair(wethAddress, tokenAddress));
        } else {
            pair = IMimoPair(_pair);
        }
        WETH.transfer(address(pair), ethAllocated);
        token.safeTransfer(address(pair), tokenAllocated);
        lpSupply = pair.mint(address(this));

        token.approve(address(ve), token.balanceOf(address(this)));

        emit LiquidityPoolCreated(
            address(pair),
            tokenAddress,
            wethAddress,
            tokenAllocated,
            ethAllocated
        );
    }

    /// @notice Withdraw liquidity pool tokens
    function withdrawLiquidity() external isStopped(false) timelockElapsed {
        require(address(pair) != address(0), "pair not created");

        UserInfo storage user = getUserInfo[msg.sender];

        uint256 balance = pairBalance(msg.sender);
        require(balance > 0, "caller has no liquidity to claim");

        user.hasWithdrawnPair = true;

        if (msg.sender == issuer) {
            emit IssuerLiquidityWithdrawn(msg.sender, address(pair), balance);
        } else {
            emit UserLiquidityWithdrawn(msg.sender, address(pair), balance);
        }

        pair.transfer(msg.sender, balance);
    }

    /// @notice Withdraw incentives tokens
    function withdrawIncentives() external {
        require(address(pair) != address(0), "pair not created");

        uint256 amount = getIncentives(msg.sender);
        require(amount > 0, "caller has no incentive to claim");

        UserInfo storage user = getUserInfo[msg.sender];
        user.hasWithdrawnIncentives = true;

        if (msg.sender == issuer) {
            tokenIncentivesBalance -= tokenIncentiveIssuerRefund;
            tokenReserve = 0;
        } else {
            tokenIncentivesBalance -= amount;
        }

        (int128 lockedAmount, ) = ve.locked(msg.sender);
        if (lockedAmount == 0) {
            ve.create_lock_for(msg.sender, amount, block.timestamp + 126144000);
        } else {
            ve.deposit_for(msg.sender, amount, address(this));
        }
        emit IncentiveTokenWithdraw(msg.sender, address(token), amount);
    }

    /// @notice Withdraw ETH if launch has been cancelled
    function emergencyWithdraw() external isStopped(true) {
        if (address(pair) == address(0)) {
            if (msg.sender != issuer) {
                UserInfo storage user = getUserInfo[msg.sender];
                require(
                    user.balance > 0,
                    "expected user to have non-zero balance to perform emergency withdraw"
                );

                uint256 balance = user.balance;
                user.balance = 0;
                ethReserve -= balance;

                _safeTransferETH(msg.sender, balance);

                emit ETHEmergencyWithdraw(msg.sender, balance);
            } else {
                uint256 balance = tokenReserve + tokenIncentivesBalance;
                tokenReserve = 0;
                tokenIncentivesBalance = 0;
                token.safeTransfer(issuer, balance);
                emit TokenEmergencyWithdraw(msg.sender, balance);
            }
        } else {
            UserInfo storage user = getUserInfo[msg.sender];

            uint256 balance = pairBalance(msg.sender);
            require(
                balance > 0,
                "caller has no liquidity to claim"
            );

            user.hasWithdrawnPair = true;

            if (msg.sender == issuer) {
                emit IssuerLiquidityWithdrawn(
                    msg.sender,
                    address(pair),
                    balance
                );
            } else {
                emit UserLiquidityWithdrawn(msg.sender, address(pair), balance);
            }

            pair.transfer(msg.sender, balance);
        }
    }

    /// @notice Stops the launch event and allows participants to withdraw deposits
    function allowEmergencyWithdraw() onlyOwner external {
        stopped = true;
        emit Stopped();
    }

    /// @notice Force balances to match tokens that were deposited, but not sent directly to the contract.
    /// Any excess tokens are sent to the penaltyCollector
    function skim() external {
        require(msg.sender == tx.origin, "EOA only");

        uint256 excessToken = token.balanceOf(address(this)) -
            tokenReserve -
            tokenIncentivesBalance;
        if (excessToken > 0) {
            token.safeTransfer(owner(), excessToken);
        }

        uint256 excessEth = address(this).balance - ethReserve;
        if (excessEth > 0) {
            _safeTransferETH(owner(), excessEth);
        }
    }

    /// @notice Returns the current penalty for early withdrawal
    /// @return The penalty to apply to a withdrawal amount
    function getPenalty() public view returns (uint256) {
        if (block.timestamp < auctionStart) {
            return 0;
        }
        uint256 timeElapsed = block.timestamp - auctionStart;
        if (timeElapsed < phaseOneNoFeeDuration) {
            return 0;
        } else if (timeElapsed < phaseOneDuration) {
            return
                ((timeElapsed - phaseOneNoFeeDuration) * maxWithdrawPenalty) /
                (phaseOneDuration - phaseOneNoFeeDuration);
        }
        return fixedWithdrawPenalty;
    }

    /// @notice Returns the incentives for a given user
    /// @param _user The user to look up
    /// @return The amount of incentives `_user` can withdraw
    function getIncentives(address _user) public view returns (uint256) {
        UserInfo memory user = getUserInfo[_user];

        if (user.hasWithdrawnIncentives) {
            return 0;
        }

        if (_user == issuer) {
            if (address(pair) == address(0)) return 0;
            return tokenIncentiveIssuerRefund + tokenReserve;
        } else {
            if (ethAllocated == 0) return 0;
            return (user.balance * tokenIncentivesForUsers) / ethAllocated;
        }
    }

    /// @notice Returns the outstanding balance of the launch event contract
    /// @return The balances of ETH and issued token held by the launch contract
    function getReserves() external view returns (uint256, uint256) {
        return (ethReserve, tokenReserve + tokenIncentivesBalance);
    }

    /// @notice The total amount of liquidity pool tokens the user can withyarnraw
    /// @param _user The address of the user to check
    /// @return The user's balance of liquidity pool token
    function pairBalance(address _user) public view returns (uint256) {
        UserInfo memory user = getUserInfo[_user];
        if (ethAllocated == 0 || user.hasWithdrawnPair) {
            return 0;
        }
        if (msg.sender == issuer) {
            return lpSupply / 2;
        }
        return (user.balance * lpSupply) / ethAllocated / 2;
    }

    /// @dev Bytecode size optimization for the `atPhase` modifier
    /// This works becuase internal functions are not in-lined in modifiers
    function _atPhase(Phase _phase) internal view {
        require(currentPhase() == _phase, "wrong phase");
    }

    /// @dev Bytecode size optimization for the `timelockElapsed` modifier
    /// This works becuase internal functions are not in-lined in modifiers
    function _timelockElapsed() internal view {
        uint256 phase3Start = auctionStart +
            phaseOneDuration +
            phaseTwoDuration;
        if (msg.sender == issuer) {
            require(
                block.timestamp > phase3Start + issuerTimelock,
                "can't withdraw before issuer's timelock"
            );
        } else {
            require(
                block.timestamp > phase3Start + userTimelock,
                "can't withdraw before user's timelock"
            );
        }
    }

    /// @dev Bytecode size optimization for the `isStopped` modifier
    /// This works becuase internal functions are not in-lined in modifiers
    function _isStopped(bool _stopped) internal view {
        if (_stopped) {
            require(stopped, "is still running");
        } else {
            require(!stopped, "stopped");
        }
    }

    /// @notice Send ETH
    /// @param _to The receiving address
    /// @param _value The amount of ETH to send
    /// @dev Will revert on failure
    function _safeTransferETH(address _to, uint256 _value) internal {
        require(
            address(this).balance - _value >= ethReserve,
            "not enough eth"
        );
        (bool success, ) = _to.call{value: _value}(new bytes(0));
        require(success, "eth transfer failed");
    }

    function setMasterChefPoint(address _masterChefPoint, uint256 _shares) onlyOwner external {
        require(
            IMasterChefPoint(_masterChefPoint).terminateBlock() <= block.number,
            "MasterChefPoint haven't terminate"
        );
        if (_masterChefPoint == address(0)) {
            pointShares = 0;
        } else {
            require(_shares >= 100, "point shares must greater that 100");
            pointShares = _shares;
        }
        masterChefPoint = IMasterChefPoint(_masterChefPoint);
    }
}

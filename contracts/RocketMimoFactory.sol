// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IRocketMimoFactory.sol";
import "./interfaces/IMimoFactory.sol";
import "./interfaces/IMimoPair.sol";
import "./interfaces/ILaunchEvent.sol";

contract RocketMimoFactory is
    IRocketMimoFactory,
    Initializable,
    OwnableUpgradeable
{
    using SafeERC20 for IERC20;

    address public override penaltyCollector;
    address public override eventImplementation;

    address public override weth;
    address public override factory;
    address public override machineFiNFT;

    uint256 public override phaseOneDuration;
    uint256 public override phaseOneNoFeeDuration;
    uint256 public override phaseTwoDuration;

    mapping(address => address) public override getRMLaunchEvent;
    mapping(address => bool) public override isRMLaunchEvent;
    address[] public override allRMLaunchEvents;

    /// @notice initializes the launch event factory
    /// @dev Uses clone factory pattern to save space
    /// @param _eventImplementation Implementation of launch event contract
    /// @param _weth WETH token address
    /// @param _penaltyCollector Address that collects all withdrawal penalties
    /// @param _factory Factory used to get info of MIMOPairs
    /// @param _machineFiNFT MachineFiNFT address
    function initialize(
        address _eventImplementation,
        address _weth,
        address _penaltyCollector,
        address _factory,
        address _machineFiNFT
    ) public initializer {
        __Ownable_init();
        require(
            _eventImplementation != address(0),
            "RocketMimoFactory: event implentation can't be zero address"
        );
        require(_weth != address(0), "RocketMimoFactory: weth can't be zero address");
        require(
            _penaltyCollector != address(0),
            "RocketMimoFactory: penalty collector can't be zero address"
        );
        require(
            _factory != address(0),
            "RocketMimoFactory: factory can't be zero address"
        );

        eventImplementation = _eventImplementation;

        weth = _weth;
        penaltyCollector = _penaltyCollector;
        factory = _factory;
        machineFiNFT = _machineFiNFT;

        phaseOneDuration = 2 days;
        phaseOneNoFeeDuration = 1 days;
        phaseTwoDuration = 1 days;
    }

    /// @notice Returns the number of launch events
    /// @return The number of launch events ever created
    function numLaunchEvents() external view override returns (uint256) {
        return allRMLaunchEvents.length;
    }

    /// @notice Creates a launch event contract
    /// @param _issuer Address of the project issuing tokens for auction
    /// @param _phaseOneStartTime Timestamp of when launch event will start
    /// @param _token Token that will be issued through this launch event
    /// @param _tokenAmountIncludingIncentives Amount of tokens that will be issued
    /// @param _tokenIncentivesPercent Additional tokens that will be given as
    /// incentive for locking up LPs during phase 3 expressed as a percentage
    /// of the issuing tokens for sale, scaled to 1e18
    /// @param _tokenIncentivesPercent is the percentage of the issued tokens for sale that will be used as incentives for locking the LP during phase 3.
    /// These incentives are on top of the tokens for sale.
    /// For example, if we issue 100 tokens for sale and 5% of incentives, then 5 tokens will be given as incentives and in total the contract should have 105 tokens
    /// @param _floorPrice Price of each token in ETH, scaled to 1e18
    /// @param _maxWithdrawPenalty Maximum withdrawal penalty that can be met
    /// during phase 1
    /// @param _fixedWithdrawPenalty Withdrawal penalty during phase 2
    /// @param _maxAllocation Maximum number of ETH each participant can commit
    /// @param _userTimelock Amount of time users' LPs will be locked for
    /// during phase 3
    /// @param _issuerTimelock Amount of time issuer's LP will be locked for
    /// during phase 3
    /// @return Address of launch event contract
    function createRMLaunchEvent(
        address _issuer,
        uint256 _phaseOneStartTime,
        address _token,
        uint256 _tokenAmountIncludingIncentives,
        uint256 _tokenIncentivesPercent,
        uint256 _floorPrice,
        uint256 _maxWithdrawPenalty,
        uint256 _fixedWithdrawPenalty,
        uint256 _maxAllocation,
        uint256 _userTimelock,
        uint256 _issuerTimelock
    ) external override onlyOwner returns (address) {
        require(
            getRMLaunchEvent[_token] == address(0),
            "RocketMimoFactory: token has already been issued"
        );
        require(_issuer != address(0), "RocketMimoFactory: issuer can't be 0 address");
        require(_token != address(0), "RocketMimoFactory: token can't be 0 address");
        require(_token != weth, "RocketMimoFactory: token can't be weth");
        require(
            _tokenAmountIncludingIncentives > 0,
            "RocketMimoFactory: token amount including incentives needs to be greater than 0"
        );

        // avoids stack too deep error
        {
            address pair = IMimoFactory(factory).getPair(_token, weth);
            require(
                pair == address(0) || IMimoPair(pair).totalSupply() == 0,
                "RocketMimoFactory: liquid pair already exists"
            );
        }

        address launchEvent = Clones.clone(eventImplementation);

        getRMLaunchEvent[_token] = launchEvent;
        isRMLaunchEvent[launchEvent] = true;
        allRMLaunchEvents.push(launchEvent);

        // msg.sender needs to approve RocketMimoFactory
        IERC20(_token).safeTransferFrom(
            msg.sender,
            launchEvent,
            _tokenAmountIncludingIncentives
        );

        emit IssuingTokenDeposited(_token, _tokenAmountIncludingIncentives);

        ILaunchEvent(launchEvent).initialize(
            _issuer,
            _phaseOneStartTime,
            _token,
            _tokenIncentivesPercent,
            _floorPrice,
            _maxWithdrawPenalty,
            _fixedWithdrawPenalty,
            _maxAllocation,
            _userTimelock,
            _issuerTimelock
        );

        _emitLaunchedEvent(launchEvent, _issuer, _token, _phaseOneStartTime);

        return launchEvent;
    }

    /// @notice Set address to collect withdrawal penalties
    /// @param _penaltyCollector New penalty collector address
    function setPenaltyCollector(address _penaltyCollector)
        external
        override
        onlyOwner
    {
        require(
            _penaltyCollector != address(0),
            "RocketMimoFactory: penalty collector can't be address zero"
        );
        penaltyCollector = _penaltyCollector;
        emit SetPenaltyCollector(_penaltyCollector);
    }

    /// @notice Set JoeFactory address
    /// @param _factory New factory address
    function setFactory(address _factory) external override onlyOwner {
        require(
            _factory != address(0),
            "RocketMimoFactory: factory can't be address zero"
        );
        factory = _factory;
        emit SetFactory(_factory);
    }

    /// @notice Set duration of each of the three phases
    /// @param _phaseNumber Can be only 1 or 2
    /// @param _duration Duration of phase in seconds
    function setPhaseDuration(uint256 _phaseNumber, uint256 _duration)
        external
        override
        onlyOwner
    {
        if (_phaseNumber == 1) {
            require(
                _duration > phaseOneNoFeeDuration,
                "RocketMimoFactory: phase one duration less than or equal to no fee duration"
            );
            phaseOneDuration = _duration;
        } else if (_phaseNumber == 2) {
            phaseTwoDuration = _duration;
        }
        emit PhaseDurationChanged(_phaseNumber, _duration);
    }

    /// @notice Set the no fee duration of phase 1
    /// @param _noFeeDuration Duration of no fee phase
    function setPhaseOneNoFeeDuration(uint256 _noFeeDuration)
        external
        override
        onlyOwner
    {
        require(
            _noFeeDuration < phaseOneDuration,
            "RocketMimoFactory: no fee duration greater than or equal to phase one duration"
        );
        phaseOneNoFeeDuration = _noFeeDuration;
        emit NoFeeDurationChanged(_noFeeDuration);
    }

    /// @notice Set the proxy implementation address
    /// @param _eventImplementation The address of the implementation contract
    function setEventImplementation(address _eventImplementation)
        external
        override
        onlyOwner
    {
        require(_eventImplementation != address(0), "RocketMimoFactory: can't be null");
        eventImplementation = _eventImplementation;
        emit SetEventImplementation(_eventImplementation);
    }

    /// @dev This function emits an event after a new launch event has been created
    /// It is only seperated out due to `createRJLaunchEvent` having too many local variables
    function _emitLaunchedEvent(
        address _launchEventAddress,
        address _issuer,
        address _token,
        uint256 _phaseOneStartTime
    ) internal {
        uint256 _phaseTwoStartTime = _phaseOneStartTime + phaseOneDuration;
        uint256 _phaseThreeStartTime = _phaseTwoStartTime + phaseTwoDuration;

        emit RMLaunchEventCreated(
            _launchEventAddress,
            _issuer,
            _token,
            _phaseOneStartTime,
            _phaseTwoStartTime,
            _phaseThreeStartTime
        );
    }
}

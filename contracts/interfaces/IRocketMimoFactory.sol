// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

interface IRocketMimoFactory {
    event RMLaunchEventCreated(
        address indexed launchEvent,
        address indexed issuer,
        address indexed token,
        uint256 phaseOneStartTime,
        uint256 phaseTwoStartTime,
        uint256 phaseThreeStartTime
    );
    event SetPenaltyCollector(address indexed collector);
    event SetRouter(address indexed router);
    event SetFactory(address indexed factory);
    event SetEventImplementation(address indexed implementation);
    event IssuingTokenDeposited(address indexed token, uint256 amount);
    event PhaseDurationChanged(uint256 phase, uint256 duration);
    event NoFeeDurationChanged(uint256 duration);

    function eventImplementation() external view returns (address);

    function penaltyCollector() external view returns (address);

    function weth() external view returns (address);

    function factory() external view returns (address);

    function machineFiNFT() external view returns (address);

    function phaseOneDuration() external view returns (uint256);

    function phaseOneNoFeeDuration() external view returns (uint256);

    function phaseTwoDuration() external view returns (uint256);

    function getRMLaunchEvent(address token)
        external
        view
        returns (address launchEvent);

    function isRMLaunchEvent(address token) external view returns (bool);

    function allRMLaunchEvents(uint256) external view returns (address pair);

    function numLaunchEvents() external view returns (uint256);

    function createRMLaunchEvent(
        address _issuer,
        uint256 _phaseOneStartTime,
        address _token,
        uint256 _tokenAmount,
        uint256 _tokenIncentivesPercent,
        uint256 _floorPrice,
        uint256 _maxWithdrawPenalty,
        uint256 _fixedWithdrawPenalty,
        uint256 _maxAllocation,
        uint256 _userTimelock,
        uint256 _issuerTimelock
    ) external returns (address pair);

    function setPenaltyCollector(address) external;

    function setFactory(address) external;

    function setPhaseDuration(uint256, uint256) external;

    function setPhaseOneNoFeeDuration(uint256) external;

    function setEventImplementation(address) external;
}

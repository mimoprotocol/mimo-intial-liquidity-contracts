// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "../interfaces/IMasterChefPoint.sol";

contract MasterChefPoint is IMasterChefPoint {
    uint256 public override terminateBlock;
    mapping (address => uint256) public override userPoints;
    uint256 public override totalPoints;

    constructor() {
        terminateBlock = block.number;
    }

    function addUserPoints(address user, uint256 points) external {
        userPoints[user] = userPoints[user] + points;
        totalPoints += points;
    }
}

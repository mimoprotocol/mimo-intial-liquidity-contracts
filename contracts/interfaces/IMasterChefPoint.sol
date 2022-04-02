// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

interface IMasterChefPoint {
    function terminateBlock() external view returns (uint256);

    function userPoints(address _user) external view returns (uint256);

    function totalPoints() external view returns (uint256);
}

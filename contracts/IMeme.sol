// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMeme {
    // 豁免税费
    function excludeFromFee(address account) external; 
    // 恢复收费
    function includeInFee(address account) external;   
    // 是否豁免
    function isExcludedFromFee(address account) external view returns(bool);
}

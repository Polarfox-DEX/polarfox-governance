pragma solidity ^0.5.16;

import "@polarfox/core/contracts/PolarfoxFactory.sol";
import "@polarfox/core/contracts/PolarfoxPair.sol";

contract PolarFactory is PolarfoxFactory {
    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }
}
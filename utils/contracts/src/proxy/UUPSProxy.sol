//SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "./AbstractProxy.sol";
import "../storage/ProxyStorage.sol";
import "../errors/AddressError.sol";
import "../helpers/AddressUtil.sol";

contract UUPSProxy is AbstractProxy, ProxyStorage {
    constructor(address firstImplementation) {
        if (firstImplementation == address(0)) {
            revert AddressError.ZeroAddress();
        }

        if (!AddressUtil.isContract(firstImplementation)) {
            revert AddressError.NotAContract(firstImplementation);
        }

        _proxyStore().implementation = firstImplementation;
    }

    function _getImplementation() internal view virtual override returns (address) {
        return _proxyStore().implementation;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PrivatePredictionMarket.sol";

contract Deploy is Script {
    // CRE Forwarder address on Sepolia
    // Source: https://docs.chain.link/cre/guides/workflow/using-evm-client/supported-networks-go
    address constant CRE_FORWARDER_SEPOLIA = 0x15fc6ae953e024d975e77382eeec56a9101f9f88;

    function run() external {
        uint256 deployerKey = vm.envUint("CRE_ETH_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        PrivatePredictionMarket market = new PrivatePredictionMarket(CRE_FORWARDER_SEPOLIA);
        console.log("PrivatePredictionMarket deployed at:", address(market));

        vm.stopBroadcast();
    }
}
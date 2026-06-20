// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {stdJson} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {NetworkInfo, SphinxConstants} from "@sphinx-labs/contracts/contracts/foundry/SphinxConstants.sol";

import {IJBSwapSplitHook} from "../../src/interfaces/IJBSwapSplitHook.sol";

/// @custom:member hook The deployed swap split hook for the selected network.
struct SwapSplitHookDeployment {
    IJBSwapSplitHook hook;
}

/// @notice Reads swap-split-hook deployment artifacts emitted by the repo's Sphinx deployment flow.
library SwapSplitHookDeploymentLib {
    // Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    // forge-lint: disable-next-line(screaming-snake-case-const)
    Vm internal constant vm = Vm(VM_ADDRESS);

    /// @notice Read the swap split hook deployment for the current chain.
    /// @param path The root path containing Sphinx deployment artifacts.
    /// @return deployment The deployment addresses for the current chain.
    function getDeployment(string memory path) internal returns (SwapSplitHookDeployment memory deployment) {
        uint256 chainId = block.chainid;

        SphinxConstants sphinxConstants = new SphinxConstants();
        NetworkInfo[] memory networks = sphinxConstants.getNetworkInfoArray();

        for (uint256 i; i < networks.length; i++) {
            if (networks[i].chainId == chainId) return getDeployment({path: path, networkName: networks[i].name});
        }

        revert("ChainID is not (currently) supported by Sphinx.");
    }

    /// @notice Read the swap split hook deployment for an explicit Sphinx network name.
    /// @param path The root path containing Sphinx deployment artifacts.
    /// @param networkName The Sphinx network name to read from.
    /// @return deployment The deployment addresses for `networkName`.
    function getDeployment(
        string memory path,
        string memory networkName
    )
        internal
        view
        returns (SwapSplitHookDeployment memory deployment)
    {
        deployment.hook = IJBSwapSplitHook(
            _getDeploymentAddress({
                path: path,
                projectName: "nana-swap-split-hook-v6",
                networkName: networkName,
                contractName: "JBSwapSplitHook"
            })
        );
    }

    /// @notice Get a deployed contract address from a Sphinx artifact.
    function _getDeploymentAddress(
        string memory path,
        string memory projectName,
        string memory networkName,
        string memory contractName
    )
        internal
        view
        returns (address deploymentAddress)
    {
        string memory deploymentJson =
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.readFile(string.concat(path, projectName, "/", networkName, "/", contractName, ".json"));

        deploymentAddress = stdJson.readAddress({json: deploymentJson, key: ".address"});
    }
}

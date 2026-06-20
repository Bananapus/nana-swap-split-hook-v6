// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CoreDeployment, CoreDeploymentLib} from "@bananapus/core-v6/script/helpers/CoreDeploymentLib.sol";
import {
    RouterTerminalDeployment,
    RouterTerminalDeploymentLib
} from "@bananapus/router-terminal-v6/script/helpers/RouterTerminalDeploymentLib.sol";
import {Sphinx} from "@sphinx-labs/contracts/contracts/foundry/SphinxPlugin.sol";
import {Script} from "forge-std/Script.sol";

import {JBSwapSplitHook} from "../src/JBSwapSplitHook.sol";

/// @notice Deploys the stateless swap split hook.
contract DeployScript is Script, Sphinx {
    /// @notice The CREATE2 salt used for the hook deployment.
    bytes32 constant SWAP_SPLIT_HOOK = "JBSwapSplitHookV6";

    /// @notice Tracks the deployed core contracts for the active chain.
    CoreDeployment core;

    /// @notice Tracks the deployed router terminal for the active chain.
    RouterTerminalDeployment router;

    /// @notice Configure the Sphinx deployment metadata for this repo.
    function configureSphinx() public override {
        sphinxConfig.projectName = "nana-swap-split-hook-v6";
        sphinxConfig.mainnets = ["ethereum", "optimism", "base", "arbitrum"];
        sphinxConfig.testnets = ["ethereum_sepolia", "optimism_sepolia", "base_sepolia", "arbitrum_sepolia"];
    }

    /// @notice Resolve dependencies and deploy the hook.
    function run() public {
        core = CoreDeploymentLib.getDeployment(
            vm.envOr({
                name: "NANA_CORE_DEPLOYMENT_PATH", defaultValue: string("node_modules/@bananapus/core-v6/deployments/")
            })
        );

        router = RouterTerminalDeploymentLib.getDeployment(
            vm.envOr({
                name: "NANA_ROUTER_TERMINAL_DEPLOYMENT_PATH",
                defaultValue: string("node_modules/@bananapus/router-terminal-v6/deployments/")
            })
        );

        deploy();
    }

    /// @notice Deploy the hook through Sphinx.
    function deploy() public sphinx {
        new JBSwapSplitHook{salt: SWAP_SPLIT_HOOK}({directory: core.directory, routerTerminal: router.terminal});
    }
}

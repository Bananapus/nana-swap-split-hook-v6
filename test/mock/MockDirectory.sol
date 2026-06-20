// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBProjects} from "@bananapus/core-v6/src/interfaces/IJBProjects.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";

/// @notice Minimal directory for hook and router tests.
contract MockDirectory is IJBDirectory {
    IJBProjects public override PROJECTS;

    mapping(uint256 projectId => mapping(address terminal => bool)) public terminalOf;
    mapping(uint256 projectId => mapping(address token => IJBTerminal terminal)) public primaryTerminal;
    mapping(uint256 projectId => IJBTerminal[] terminals) internal _terminalsOf;

    function setIsTerminal(uint256 projectId, IJBTerminal terminal, bool flag) external {
        terminalOf[projectId][address(terminal)] = flag;

        if (flag) _terminalsOf[projectId].push(terminal);
    }

    function setPrimaryTerminal(uint256 projectId, address token, IJBTerminal terminal) external {
        primaryTerminal[projectId][token] = terminal;
    }

    function controllerOf(uint256) external pure override returns (IERC165) {
        return IERC165(address(0));
    }

    function isAllowedToSetFirstController(address) external pure override returns (bool) {
        return false;
    }

    function isTerminalOf(uint256 projectId, IJBTerminal terminal) external view override returns (bool) {
        return terminalOf[projectId][address(terminal)];
    }

    function primaryTerminalOf(uint256 projectId, address token) external view override returns (IJBTerminal) {
        return primaryTerminal[projectId][token];
    }

    function terminalsOf(uint256 projectId) external view override returns (IJBTerminal[] memory) {
        return _terminalsOf[projectId];
    }

    function setControllerOf(uint256, IERC165) external pure override {}

    function setIsAllowedToSetFirstController(address, bool) external pure override {}

    function setPrimaryTerminalOf(uint256, address, IJBTerminal) external pure override {}

    function setTerminalsOf(uint256, IJBTerminal[] calldata) external pure override {}
}

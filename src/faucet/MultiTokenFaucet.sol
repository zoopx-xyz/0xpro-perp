// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MultiTokenFaucet
/// @notice Owner-controlled faucet that holds pre-funded token balances and dispenses
///         fixed per-token drops with a per-address cooldown.
contract MultiTokenFaucet is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct DropCfg {
        uint256 amount; // token base units to send per claim
        bool enabled; // whether dispensing is enabled for this token
    }

    // token => drop config
    mapping(address => DropCfg) public drops;
    // token => account => last claim timestamp
    mapping(address => mapping(address => uint256)) public lastClaimAt;

    // canonical list of tokens configured (for UIs)
    address[] private _tokenList;
    mapping(address => bool) private _listed;

    // global cooldown per token per wallet (defaults to 1 day)
    uint256 public cooldownSec = 1 days;

    event TokenListed(address indexed token);
    event DropConfigured(address indexed token, uint256 amount, bool enabled);
    event CooldownUpdated(uint256 cooldownSec);
    event Dispensed(address indexed token, address indexed to, uint256 amount, uint256 nextClaimAt);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);

    constructor(address owner_) {
        _transferOwnership(owner_);
    }

    function tokenList() external view returns (address[] memory) {
        return _tokenList;
    }

    function setCooldown(uint256 secs) external onlyOwner {
        cooldownSec = secs;
        emit CooldownUpdated(secs);
    }

    function setDrop(address token, uint256 amount, bool enabled) public onlyOwner {
        drops[token] = DropCfg({amount: amount, enabled: enabled});
        if (!_listed[token]) {
            _listed[token] = true;
            _tokenList.push(token);
            emit TokenListed(token);
        }
        emit DropConfigured(token, amount, enabled);
    }

    function setDrops(address[] calldata tokens, uint256[] calldata amounts, bool[] calldata enabled)
        external
        onlyOwner
    {
        require(tokens.length == amounts.length && tokens.length == enabled.length, "len mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            setDrop(tokens[i], amounts[i], enabled[i]);
        }
    }

    function getNextClaimAt(address token, address user) external view returns (uint256 nextClaimAt, uint256 remains) {
        uint256 last = lastClaimAt[token][user];
        if (last == 0) return (0, 0);
        uint256 next_ = last + cooldownSec;
        if (block.timestamp >= next_) return (0, 0);
        return (next_, next_ - block.timestamp);
    }

    /// @dev Internal dispense without reentrancy guard to enable batch calls from a guarded entry.
    function _dispense(address to, address token) internal returns (uint256 sent) {
        DropCfg memory cfg = drops[token];
        if (!cfg.enabled || cfg.amount == 0) return 0;

        uint256 last = lastClaimAt[token][to];
        if (last != 0 && block.timestamp < last + cooldownSec) return 0; // still cooling down

        uint256 bal = IERC20(token).balanceOf(address(this));
        require(bal >= cfg.amount, "faucet balance low");

        lastClaimAt[token][to] = block.timestamp;
        IERC20(token).safeTransfer(to, cfg.amount);
        emit Dispensed(token, to, cfg.amount, block.timestamp + cooldownSec);
        return cfg.amount;
    }

    /// @notice Dispense a single token drop to `to`. Only callable by owner (backend signer).
    function dispense(address to, address token) public onlyOwner nonReentrant returns (uint256 sent) {
        return _dispense(to, token);
    }

    /// @notice Batch dispense for a selection of tokens. Skips tokens in cooldown or disabled.
    function dispenseMany(address to, address[] calldata tokens)
        external
        onlyOwner
        nonReentrant
        returns (uint256 tokensSent, uint256 totalAmount)
    {
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 amt = _dispense(to, tokens[i]);
            if (amt > 0) {
                tokensSent++;
                totalAmount += amt;
            }
        }
    }

    /// @notice Withdraw tokens from faucet (admin-only).
    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(token, to, amount);
    }
}

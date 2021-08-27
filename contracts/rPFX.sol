// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import './interfaces/IERC20.sol';

/**
 * The Polarfox reward token ($rPFX) contract. 🦊
 *
 * This token is a symbolic version of PFX. When Polarfox launches, those tokens will be convertible 1:1 to PFX.
 * It will be used a reward system until then.
 *
 * 500,000 rPFX will be minted, which will then be converted to 500,000 PFX, amounting to 1.7% of the total
 * PFX supply.
 */
contract rPFX is IERC20 {
    /// @notice EIP-20 token name for this token
    string public constant name = 'Polarfox Reward Token';

    /// @notice EIP-20 token symbol for this token
    string public constant symbol = 'rPFX';

    /// @notice EIP-20 token decimals for this token
    uint8 public constant decimals = 18;

    /// @notice Initial number of tokens in circulation
    uint256 public constant override totalSupply = 500_000e18; // 500,000 rPFX

    /// @dev Allowance amounts on behalf of others
    mapping(address => mapping(address => uint96)) internal allowances;

    /// @dev Official record of token balances for each account
    mapping(address => uint96) internal balances;

    /**
     * @notice Construct a new rPFX token
     */
    constructor() {
        // All the tokens are sent to msg.sender
        balances[msg.sender] = uint96(totalSupply);

        emit Transfer(address(0), msg.sender, totalSupply);
    }

    /**
     * @notice Get the number of tokens `spender` is approved to spend on behalf of `account`
     * @param account The address of the account holding the funds
     * @param spender The address of the account spending the funds
     * @return The number of tokens approved
     */
    function allowance(address account, address spender) external view override returns (uint256) {
        return allowances[account][spender];
    }

    /**
     * @notice Approve `spender` to transfer up to `amount` from `src`
     * @dev This will overwrite the approval amount for `spender`
     *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * @param spender The address of the account which may transfer tokens
     * @param rawAmount The number of tokens that are approved (2^256-1 means infinite)
     * @return Whether or not the approval succeeded
     */
    function approve(address spender, uint256 rawAmount) external override returns (bool) {
        uint96 amount;
        if (rawAmount == type(uint256).max) {
            amount = type(uint96).max;
        } else {
            amount = safe96(rawAmount, 'rPFX::approve: amount exceeds 96 bits');
        }

        allowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Get the number of tokens held by the `account`
     * @param account The address of the account to get the balance of
     * @return The number of tokens held
     */
    function balanceOf(address account) external view override returns (uint256) {
        return balances[account];
    }

    /**
     * @notice Transfer `amount` tokens from `msg.sender` to `dst`
     * @param dst The address of the destination account
     * @param rawAmount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(address dst, uint256 rawAmount) external override returns (bool) {
        uint96 amount = safe96(rawAmount, 'rPFX::transfer: amount exceeds 96 bits');
        _transferTokens(msg.sender, dst, amount);
        return true;
    }

    /**
     * @notice Transfer `amount` tokens from `src` to `dst`
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param rawAmount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(
        address src,
        address dst,
        uint256 rawAmount
    ) external override returns (bool) {
        address spender = msg.sender;
        uint96 spenderAllowance = allowances[src][spender];
        uint96 amount = safe96(rawAmount, 'rPFX::approve: amount exceeds 96 bits');

        if (spender != src && spenderAllowance != type(uint96).max) {
            require(spenderAllowance >= amount, 'rPFX::transferFrom: transfer amount exceeds spender allowance');
            uint96 newAllowance;

            unchecked {
                newAllowance = spenderAllowance - amount;
            }

            allowances[src][spender] = newAllowance;

            emit Approval(src, spender, newAllowance);
        }

        _transferTokens(src, dst, amount);
        return true;
    }

    // Internal transfer mechanism call and safety checks
    function _transferTokens(
        address src,
        address dst,
        uint96 amount
    ) internal {
        require(src != address(0), 'rPFX::_transferTokens: cannot transfer from the zero address');
        require(balances[src] >= amount, 'rPFX::_transferExcluded: transfer amount exceeds balance');

        // Will never overflow
        unchecked {
            balances[src] -= amount;
            balances[dst] += amount;
        }

        emit Transfer(src, dst, amount);
    }

    function safe96(uint256 n, string memory errorMessage) internal pure returns (uint96) {
        require(n < 2**96, errorMessage);
        return uint96(n);
    }

    function getChainId() internal view returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}

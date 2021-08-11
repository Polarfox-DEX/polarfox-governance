// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import './Ownable.sol';
import './IPFX.sol';
import './IERC20.sol';

// TODO: See if further improvements can be made using Solidity 0.8.6
// TODO: Use +=, -=, x=, /= whenever possible
// TODO: Add proper introductory comment
// TODO: Add event when excluding from / including in fees
// TODO: Add other events
// TODO: Write: this contract is not using SafeMath because we are using Solidity >= 0.8.0
// TODO: Add comments to functions
// TODO: Think: should the setters for the dev and PRF addresses be available to the owner of this contract or to said addresses themselves?

contract PFX is Ownable, IPFX, IERC20 {
    /// @notice EIP-20 token name for this token
    string public constant name = 'Polarfox';

    /// @notice EIP-20 token symbol for this token
    string public constant symbol = 'PFX';

    /// @notice EIP-20 token decimals for this token
    uint8 public constant decimals = 18;

    /// @notice Initial number of tokens in circulation
    uint256 public constant override totalSupply = 30_000_000e18; // 30 million PFX

    /// @notice Maximum value for the LP reflection fee - it cannot be set up above this number
    uint96 public constant maximumReflectionFee = 100; // 10% = 100/1000

    /// @notice Maximum value for the dev fee - it cannot be set up above this number
    uint96 public constant maximumDevFee = 10; // 1% = 10/1000

    /// @notice Current reflection fee
    uint96 public reflectionFee;

    /// @notice Reflection address - the address that receives the reflection fees
    address public reflectionAddress;

    /// @notice Current dev funding fee
    uint96 public devFee;

    /// @notice Dev address - the address that receives the dev funding fees
    address public devAddress;

    /// @notice True if the token is reflecting to PFX-LP holders, false otherwise
    bool public isReflecting;

    /// @notice True if dev fees are charged, false otherwise
    bool public isChargingDevFees;

    /// @notice IsExcludedSrc - the addresses that are excluded from the reflection / dev fees when sending transactions
    mapping(address => bool) public isExcludedSrc;

    /// @notice IsExcludedDst - the addresses that are excluded from the reflection / dev fees when receiving transactions
    mapping(address => bool) public isExcludedDst;

    /// @dev Allowance amounts on behalf of others
    mapping(address => mapping(address => uint96)) internal allowances;

    /// @dev Official record of token balances for each account
    mapping(address => uint96) internal balances;

    /// @notice A record of each accounts delegate
    mapping(address => address) public delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint96 votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping(address => uint32) public numCheckpoints;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256('EIP712Domain(string name,uint256 chainId,address verifyingContract)');

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256('Delegation(address delegatee,uint256 nonce,uint256 expiry)');

    /// @notice The EIP-712 typehash for the permit struct used by the contract
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)');

    /// @notice A record of states for signing / validating signatures
    mapping(address => uint256) public nonces;

    /**
     * @notice Construct a new PFX token
     * @param _devAddress The initial account to grant all the tokens
     */
    constructor(address _devAddress) {
        // All the tokens are sent to msg.sender
        balances[msg.sender] = uint96(totalSupply);

        // The reflection address is temporarily set to msg.sender
        reflectionAddress = msg.sender;

        // The dev address is the address which will receive the dev fees
        devAddress = _devAddress;

        // Initial values for reflection and dev fees
        reflectionFee = 9; // 0.9% = 9/1000
        devFee = 1; // 0.1% = 1/1000

        // Turn on reflection and dev fees
        isReflecting = true;
        isChargingDevFees = true;

        // Exclude contract creator address and dev address from fees
        isExcludedSrc[msg.sender] = true;
        isExcludedSrc[_devAddress] = true;
        isExcludedDst[msg.sender] = true;
        isExcludedDst[_devAddress] = true;

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
            amount = safe96(rawAmount, 'PFX::approve: amount exceeds 96 bits');
        }

        allowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Triggers an approval from owner to spend
     * @param owner The address to approve from
     * @param spender The address to be approved
     * @param rawAmount The number of tokens that are approved (2^256-1 means infinite)
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function permit(
        address owner,
        address spender,
        uint256 rawAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        uint96 amount;
        if (rawAmount == type(uint256).max) {
            amount = type(uint96).max;
        } else {
            amount = safe96(rawAmount, 'PFX::permit: amount exceeds 96 bits');
        }

        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, rawAmount, nonces[owner]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked('\x19\x01', domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), 'PFX::permit: invalid signature');
        require(signatory == owner, 'PFX::permit: unauthorized');
        require(block.timestamp <= deadline, 'PFX::permit: signature expired');

        allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
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
        uint96 amount = safe96(rawAmount, 'PFX::transfer: amount exceeds 96 bits');
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
        uint96 amount = safe96(rawAmount, 'PFX::approve: amount exceeds 96 bits');

        if (spender != src && spenderAllowance != type(uint96).max) {
            require(spenderAllowance >= amount, 'PFX::transferFrom: transfer amount exceeds spender allowance');
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

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) public override {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked('\x19\x01', domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), 'PFX::delegateBySig: invalid signature');
        require(nonce == nonces[signatory]++, 'PFX::delegateBySig: invalid nonce');
        require(block.timestamp <= expiry, 'PFX::delegateBySig: signature expired');
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view override returns (uint96) {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint256 blockNumber) public view override returns (uint96) {
        require(blockNumber < block.number, 'PFX::getPriorVotes: not yet determined');

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // Ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        uint96 delegatorBalance = balances[delegator];
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    // Internal transfer mechanism call and safety checks
    function _transferTokens(
        address src,
        address dst,
        uint96 amount
    ) internal {
        require(src != address(0), 'PFX::_transferTokens: cannot transfer from the zero address');

        if (isExcludedSrc[src] || isExcludedDst[dst]) _transferExcluded(src, dst, amount);
        else _transferStandard(src, dst, amount);

        emit Transfer(src, dst, amount);

        _moveDelegates(delegates[src], delegates[dst], amount);
    }

    // Internal transfer mechanism with fees
    function _transferStandard(
        address src,
        address dst,
        uint96 amount
    ) private {
        uint96 reflectionAmount = 0;
        uint96 devAmount = 0;

        // Get 100% of the tokens
        require(balances[src] >= amount, 'PFX::_transferStandard: transfer amount exceeds balance');

        unchecked {
            balances[src] -= amount;
        }

        if (isReflecting) {
            // Calculate reflection amount
            reflectionAmount = (amount * reflectionFee) / 1000;

            // Send reflection amount to the reflection address
            balances[reflectionAddress] += reflectionAmount;
        }

        if (isChargingDevFees) {
            // Calculate dev amount
            devAmount = (amount * devFee) / 1000;

            // Send dev amount to the dev address
            balances[devAddress] += devAmount;
        }

        // Send the rest to the recipient
        balances[dst] += amount - reflectionAmount - devAmount;
    }

    // Internal transfer mechanism without fees
    function _transferExcluded(
        address src,
        address dst,
        uint96 amount
    ) private {
        // Get 100% of the tokens
        require(balances[src] >= amount, 'PFX::_transferExcluded: transfer amount exceeds balance');

        unchecked {
            balances[src] -= amount;
        }

        // Send 100% to the recipient
        balances[dst] += amount;
    }

    function includeSrc(address account) public override onlyOwner {
        isExcludedSrc[account] = false;
    }

    function includeDst(address account) public override onlyOwner {
        isExcludedDst[account] = false;
    }

    function excludeSrc(address account) public override onlyOwner {
        isExcludedSrc[account] = true;
    }

    function excludeDst(address account) public override onlyOwner {
        isExcludedDst[account] = true;
    }

    function setReflectionFee(uint96 _reflectionFee) public override onlyOwner {
        require(_reflectionFee < maximumReflectionFee, 'PFX::setReflectionFee: new reflection fee exceeds maximum reflection fee');
        reflectionFee = _reflectionFee;
    }

    function setDevFee(uint96 _devFee) public override onlyOwner {
        require(_devFee < maximumDevFee, 'PFX::setDevFee: new dev fee exceeds maximum dev fee');
        devFee = _devFee;
    }

    function setReflectionAddress(address _reflectionAddress) public override {
        // Only callable by the reflection address
        require(msg.sender == reflectionAddress, 'PFX::setReflectionAddress: can only be called by the reflection address');
        reflectionAddress = _reflectionAddress;
    }

    function setDevAddress(address _devAddress) public override {
        // Only callable by the dev fee address
        require(msg.sender == devAddress, 'PFX::setDevAddress: can only be called by the dev address');
        devAddress = _devAddress;
    }

    function startReflecting() public override onlyOwner {
        isReflecting = true;
    }

    function stopReflecting() public override onlyOwner {
        isReflecting = false;
    }

    function startDevFees() public override onlyOwner {
        isChargingDevFees = true;
    }

    function stopDevFees() public override onlyOwner {
        isChargingDevFees = false;
    }

    function _moveDelegates(
        address srcRep,
        address dstRep,
        uint96 amount
    ) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint96 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint96 srcRepNew = srcRepOld - amount;
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint96 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint96 dstRepNew = dstRepOld + amount;
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint96 oldVotes,
        uint96 newVotes
    ) internal {
        uint32 blockNumber = safe32(block.number, 'PFX::_writeCheckpoint: block number exceeds 32 bits');

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint256 n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
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

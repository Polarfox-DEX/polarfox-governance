// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import './SafeMath.sol';
import './Ownable.sol';
import './IERC20.sol';

// TODO: imports
// TODO: crank up to 0.8.6
// TODO: make ERC20 - make sure all methods are overriden properly
// TODO: remove ABIEncoderV2 if possible
// TODO: kill all TODOs

contract PFX is Ownable, IERC20 {
    /// @notice EIP-20 token name for this token
    string public constant name = 'Polarfox';

    /// @notice EIP-20 token symbol for this token
    string public constant symbol = 'PFX';

    /// @notice EIP-20 token decimals for this token
    uint8 public constant decimals = 18;

    /// @notice Initial number of tokens in circulation
    uint256 public constant initialSupply = 30_000_000e18; // 30 million PFX

    /// @notice Maximum value for the burn fee - it cannot be set up above this number
    uint96 public constant maximumBurnFee = 20; // 5% = 1/20

    /// @notice Maximum value for the dev fee - it cannot be set up above this number
    uint96 public constant maximumDevFee = 1000; // 0.1% = 1/1000

    /// @notice Current number of tokens in circulation
    uint256 public totalSupply_;

    /// @notice Current burn fee
    uint96 public burnFee;

    /// @notice Current dev funding fee
    uint96 public devFee;

    /// @notice Dev address - the address that receives the dev funding fees
    address public devAddress;

    /// @notice True if the token is burning, false otherwise
    bool public isBurning;

    /// @notice True if dev fees are charged, false otherwise
    bool public chargeDevFees;

    /// @notice IsExcludedSrc - the addresses that are excluded from the burn / dev fees when sending transactions
    mapping(address => bool) public isExcludedSrc;

    /// @notice IsExcludedDst - the addresses that are excluded from the burn / dev fees when receiving transactions
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

    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    /// @notice The standard EIP-20 transfer event
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice The standard EIP-20 approval event
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /**
     * @notice Construct a new PFX token
     * @param _devAddress The initial account to grant all the tokens
     */
    constructor(address _devAddress) public {
        // All the tokens are sent to msg.sender
        balances[msg.sender] = uint96(initialSupply);

        // The dev address is the address which will receive the dev fees
        devAddress = _devAddress;
        totalSupply_ = initialSupply;

        burnFee = 370; // 0.27% = 1/370
        devFee = 3333; // 0.03% = 1/3333

        isBurning = true;
        chargeDevFees = true;

        isExcludedSrc[msg.sender] = true;
        isExcludedSrc[_devAddress] = true;

        isExcludedDst[msg.sender] = true;
        isExcludedDst[_devAddress] = true;

        emit Transfer(address(0), _devAddress, initialSupply);
    }

    /**
     * @notice Returns the amount of tokens in existence.
     */
    function totalSupply() external view override returns (uint256) {
        // TODO: code a proper total supply method. Return the 30,000,000 minus the amount of tokens sent to burn addresses (list all burn addresses)
        return totalSupply_;
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
        if (rawAmount == uint256(-1)) {
            amount = uint96(-1);
        } else {
            amount = safe96(rawAmount, 'Pfx::approve: amount exceeds 96 bits');
        }

        allowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Triggers an approval from owner to spends
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
    ) external {
        uint96 amount;
        if (rawAmount == uint256(-1)) {
            amount = uint96(-1);
        } else {
            amount = safe96(rawAmount, 'Pfx::permit: amount exceeds 96 bits');
        }

        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, rawAmount, nonces[owner]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked('\x19\x01', domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), 'Pfx::permit: invalid signature');
        require(signatory == owner, 'Pfx::permit: unauthorized');
        require(now <= deadline, 'Pfx::permit: signature expired');

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
        uint96 amount = safe96(rawAmount, 'Pfx::transfer: amount exceeds 96 bits');
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
        uint96 amount = safe96(rawAmount, 'Pfx::approve: amount exceeds 96 bits');

        if (spender != src && spenderAllowance != uint96(-1)) {
            uint96 newAllowance = sub96(spenderAllowance, amount, 'Pfx::transferFrom: transfer amount exceeds spender allowance');
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
    function delegate(address delegatee) public {
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
    ) public {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), getChainId(), address(this)));
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = keccak256(abi.encodePacked('\x19\x01', domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), 'Pfx::delegateBySig: invalid signature');
        require(nonce == nonces[signatory]++, 'Pfx::delegateBySig: invalid nonce');
        require(now <= expiry, 'Pfx::delegateBySig: signature expired');
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint96) {
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
    function getPriorVotes(address account, uint256 blockNumber) public view returns (uint96) {
        require(blockNumber < block.number, 'Pfx::getPriorVotes: not yet determined');

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
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
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
        require(src != address(0), 'Pfx::_transferTokens: cannot transfer from the zero address');

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
        uint96 burnAmount = 0;
        uint96 devAmount = 0;

        // Get 100% of the tokens
        balances[src] = sub96(balances[src], amount, 'Pfx::_transferStandard: transfer amount exceeds balance');

        if (isBurning) {
            // Burn (100/burnFee)% = send them to the zero address
            burnAmount = div96(amount, burnFee, 'Pfx::_transferStandard: burn calculation failed');
            balances[address(0)] = add96(balances[address(0)], burnAmount, 'Pfx::_transferStandard: burn failed');
            // Reduce the total supply accordingly
            totalSupply_ = SafeMath.sub(totalSupply_, uint256(burnAmount), 'Pfx::_transferStandard: total supply reduction failed');
        }

        if (chargeDevFees) {
            // Send (100/devFee)%  to the dev wallet
            devAmount = div96(amount, devFee);
            balances[devAddress] = add96(balances[devAddress], devAmount, 'Pfx::_transferStandard: dev transfer failed');
        }

        // Send the rest to the recipient
        uint96 rest = sub96(
            sub96(amount, burnAmount, 'Pfx::_transferStandard: transfer amount overflows - 1'),
            devAmount,
            'Pfx::_transferStandard: transfer amount overflows - 2'
        );
        balances[dst] = add96(balances[dst], rest, 'Pfx::_transferStandard: transfer amount overflows - 3');
    }

    // Internal transfer mechanism without fees
    function _transferExcluded(
        address src,
        address dst,
        uint96 amount
    ) private {
        // Get 100% of the tokens
        balances[src] = sub96(balances[src], amount, 'Pfx::_transferExcluded: transfer amount exceeds balance');

        // Send 100% to the recipient
        balances[dst] = add96(balances[dst], amount, 'Pfx::_transferExcluded: transfer amount overflows');
    }

    function includeSrc(address account) public onlyOwner {
        isExcludedSrc[account] = false;
    }

    function includeDst(address account) public onlyOwner {
        isExcludedDst[account] = false;
    }

    function excludeSrc(address account) public onlyOwner {
        isExcludedSrc[account] = true;
    }

    function excludeDst(address account) public onlyOwner {
        isExcludedDst[account] = true;
    }

    function setBurnFee(uint96 _burnFee) public onlyOwner {
        // burnFee > maximumBurnFee => 1/burnFee < 1/maximumBurnFee
        require(_burnFee > maximumBurnFee, 'Pfx::setBurnFee: new burn fee exceeds maximum burn fee');
        burnFee = _burnFee;
    }

    function setDevFee(uint96 _devFee) public onlyOwner {
        // devFee > maximumDevFee => 1/devFee < 1/maximumDevFee
        require(_devFee > maximumDevFee, 'Pfx::setDevFee: new dev fee exceeds maximum dev fee');
        devFee = _devFee;
    }

    function setDevAddress(address _devAddress) public {
        // Only callable by the dev fee address
        require(msg.sender == devAddress, 'Pfx::setDevAddress: can only be called by the dev address');
        devAddress = _devAddress;
    }

    function startBurning() public onlyOwner {
        isBurning = true;
    }

    function stopBurning() public onlyOwner {
        isBurning = false;
    }

    function startDevFees() public onlyOwner {
        chargeDevFees = true;
    }

    function stopDevFees() public onlyOwner {
        chargeDevFees = false;
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
                uint96 srcRepNew = sub96(srcRepOld, amount, 'Pfx::_moveVotes: vote amount underflows');
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint96 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint96 dstRepNew = add96(dstRepOld, amount, 'Pfx::_moveVotes: vote amount overflows');
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
        uint32 blockNumber = safe32(block.number, 'Pfx::_writeCheckpoint: block number exceeds 32 bits');

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

    function add96(
        uint96 a,
        uint96 b,
        string memory errorMessage
    ) internal pure returns (uint96) {
        uint96 c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub96(
        uint96 a,
        uint96 b,
        string memory errorMessage
    ) internal pure returns (uint96) {
        require(b <= a, errorMessage);
        return a - b;
    }

    function div96(uint96 a, uint96 b) internal pure returns (uint96) {
        return div96(a, b, 'SafeMath: division by zero (uint96)');
    }

    function div96(
        uint96 a,
        uint96 b,
        string memory errorMessage
    ) internal pure returns (uint96) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint96 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    function getChainId() internal pure returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}

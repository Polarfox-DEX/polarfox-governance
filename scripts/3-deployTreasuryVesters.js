const Web3 = require('web3')

const { IS_PRODUCTION, CHAIN_ID, getProvider } = require('./const')
const {
    TEAM_TREASURY_MULTISIG_ADDR,
    LIQUIDITY_MINING_MULTISIG_ADDR,
    GOVERNANCE_TREASURY_MULTISIG_ADDR,
    PFX,
    TREASURY_1_START,
    TREASURY_2_START,
    TREASURY_3_START,
    TREASURY_4_START,
    TREASURY_4_END,
    TREASURY_1_VESTING_AMOUNT,
    TREASURY_2_VESTING_AMOUNT,
    TREASURY_3_VESTING_AMOUNT,
    TREASURY_4_VESTING_AMOUNT,
    TEAM_TREASURY_START,
    TEAM_TREASURY_END,
    TEAM_TREASURY_VESTING_AMOUNT
} = require('./governanceConstants')

const treasuryVester = require('../artifacts/contracts/TreasuryVester.sol/TreasuryVester.json')
const pairTreasuryVester = require('../artifacts/contracts/PairTreasuryVester.sol/PairTreasuryVester.json')

const chainId = IS_PRODUCTION ? CHAIN_ID.AVALANCHE : CHAIN_ID.FUJI

const provider = getProvider(chainId)

const web3 = new Web3(provider)

const deployTreasuryVesters = async () => {
    try {
        const accounts = await web3.eth.getAccounts()

        console.log('Attempting to deploy treasury vesters from the account', accounts[0])

        await deployPairTreasuryVester(accounts, '1', '917', TREASURY_1_VESTING_AMOUNT, TREASURY_1_START, TREASURY_2_START)
        await deployPairTreasuryVester(accounts, '2', '922', TREASURY_2_VESTING_AMOUNT, TREASURY_2_START, TREASURY_3_START)
        await deployPairTreasuryVester(accounts, '3', '922', TREASURY_3_VESTING_AMOUNT, TREASURY_3_START, TREASURY_4_START)
        await deployPairTreasuryVester(accounts, '4', '922', TREASURY_4_VESTING_AMOUNT, TREASURY_4_START, TREASURY_4_END)
        await deployTreasuryVester(accounts, TEAM_TREASURY_VESTING_AMOUNT, TEAM_TREASURY_START, TEAM_TREASURY_END)
    } catch (error) {
        console.error('An error occurred in deployTreasuryVesters():\n', error)
    }
}

deployTreasuryVesters()

async function deployPairTreasuryVester(accounts, index, liquidityMiningWeight, vestingAmount, vestingBegin, vestingEnd) {
    const deployedPairTreasuryVester = await new web3.eth.Contract(pairTreasuryVester.abi)
        .deploy({
            data: pairTreasuryVester.bytecode,
            arguments: [
                PFX[chainId], // address pfx_
                LIQUIDITY_MINING_MULTISIG_ADDR[chainId], // address liquidityMiningRecipient_
                GOVERNANCE_TREASURY_MULTISIG_ADDR[chainId], // address governanceTreasuryRecipient_
                liquidityMiningWeight, // uint liquidityMiningWeight_
                vestingAmount, // uint vestingAmount_
                vestingBegin, // uint vestingBegin_
                vestingBegin, // uint vestingCliff_
                vestingEnd // uint vestingEnd_
            ]
        })
        .send({
            from: accounts[0]
        })

    console.log(`Pair treasury vester ${index} deployed to`, deployedPairTreasuryVester.options.address)
}

async function deployTreasuryVester(accounts, vestingAmount, vestingBegin, vestingEnd) {
    const deployedTreasuryVester = await new web3.eth.Contract(treasuryVester.abi)
        .deploy({
            data: treasuryVester.bytecode,
            arguments: [
                PFX[chainId], // address pfx_
                TEAM_TREASURY_MULTISIG_ADDR[chainId], // address recipient_
                vestingAmount, // uint vestingAmount_
                vestingBegin, // uint vestingBegin_
                vestingBegin, // uint vestingCliff_
                vestingEnd // uint vestingEnd_
            ]
        })
        .send({
            from: accounts[0]
        })

    console.log(`Team treasury vester deployed to`, deployedTreasuryVester.options.address)
}

const Web3 = require('web3')

const { IS_PRODUCTION, CHAIN_ID, getProvider, EIGHTEEN_ZEROS } = require('./const')
const {
    PFX,
    TEAM_TREASURY_MULTISIG_ADDR,
    LIQUIDITY_MINING_MULTISIG_ADDR,
    AIRDROP_ADDR,
    TREASURY_1_VESTING_AMOUNT,
    TREASURY_2_VESTING_AMOUNT,
    TREASURY_3_VESTING_AMOUNT,
    TREASURY_4_VESTING_AMOUNT,
    TREASURY_VESTER_1,
    TREASURY_VESTER_2,
    TREASURY_VESTER_3,
    TREASURY_VESTER_4
} = require('./governanceConstants')

const pfxContract = require('../artifacts/contracts/PFX.sol/Pfx.json')

const chainId = IS_PRODUCTION ? CHAIN_ID.AVALANCHE : CHAIN_ID.FUJI

const provider = getProvider(chainId)

const web3 = new Web3(provider)

const allocatePfx = async () => {
    const pfx = new web3.eth.Contract(pfxContract.abi, PFX[chainId])

    try {
        console.log('Excluding', address, 'in full')

        await transfer(accounts, pfx, TEAM_TREASURY_MULTISIG_ADDR, '1500000' + EIGHTEEN_ZEROS)
        await transfer(accounts, pfx, LIQUIDITY_MINING_MULTISIG_ADDR, '200000' + EIGHTEEN_ZEROS)
        await transfer(accounts, pfx, AIRDROP_ADDR, '18000000' + EIGHTEEN_ZEROS)
        await transfer(accounts, pfx, TREASURY_VESTER_1, TREASURY_1_VESTING_AMOUNT)
        await transfer(accounts, pfx, TREASURY_VESTER_2, TREASURY_2_VESTING_AMOUNT)
        await transfer(accounts, pfx, TREASURY_VESTER_3, TREASURY_3_VESTING_AMOUNT)
        await transfer(accounts, pfx, TREASURY_VESTER_4, TREASURY_4_VESTING_AMOUNT)

        console.log('Done!')
    } catch (error) {
        console.log('An error occurred in excludeAirdropFull():', error)
    }
}

allocatePfx()

async function transfer(accounts, pfx, address, amount) {
    console.log(`Sending ${amount} PFX to ${address}...`)

    await pfx.methods.transfer(
        address // The account to exclude from fees as source
    )
    .send({
        from: accounts[0]
    })

    console.log(`Successfully sent ${amount} PFX to ${address}`)
}
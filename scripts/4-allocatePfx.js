const Web3 = require('web3')

const { IS_PRODUCTION, CHAIN_ID, getProvider } = require('./const')
const {
    PFX,
    LIQUIDITY_MINING_MULTISIG_ADDR,
    AIRDROP_ADDR,
    TREASURY_1_VESTING_AMOUNT,
    TREASURY_2_VESTING_AMOUNT,
    TREASURY_3_VESTING_AMOUNT,
    TREASURY_4_VESTING_AMOUNT,
    TREASURY_VESTER_1,
    TREASURY_VESTER_2,
    TREASURY_VESTER_3,
    TREASURY_VESTER_4,
    TEAM_TREASURY,
    TEAM_TREASURY_VESTING_AMOUNT,
    FIRST_LIQUIDITY_MINING_AMOUNT,
    AIRDROP_AMOUNT
} = require('./governanceConstants')

const pfxContract = require('../artifacts/contracts/PFX.sol/Pfx.json')

const chainId = IS_PRODUCTION ? CHAIN_ID.AVALANCHE : CHAIN_ID.FUJI

const provider = getProvider(chainId)

const web3 = new Web3(provider)

const allocatePfx = async () => {
    const accounts = await web3.eth.getAccounts()
    const pfx = new web3.eth.Contract(pfxContract.abi, PFX[chainId])

    try {
        console.log('Allocating PFX')

        await transfer(accounts, pfx, 'liquidity mining multisig', LIQUIDITY_MINING_MULTISIG_ADDR[chainId], FIRST_LIQUIDITY_MINING_AMOUNT)
        await transfer(accounts, pfx, 'airdrop', AIRDROP_ADDR[chainId], AIRDROP_AMOUNT)
        await transfer(accounts, pfx, 'treasury vester #1', TREASURY_VESTER_1[chainId], TREASURY_1_VESTING_AMOUNT)
        await transfer(accounts, pfx, 'treasury vester #2', TREASURY_VESTER_2[chainId], TREASURY_2_VESTING_AMOUNT)
        await transfer(accounts, pfx, 'treasury vester #3', TREASURY_VESTER_3[chainId], TREASURY_3_VESTING_AMOUNT)
        await transfer(accounts, pfx, 'treasury vester #4', TREASURY_VESTER_4[chainId], TREASURY_4_VESTING_AMOUNT)
        await transfer(accounts, pfx, 'team treasury vester', TEAM_TREASURY[chainId], TEAM_TREASURY_VESTING_AMOUNT)

        console.log('Done!')
    } catch (error) {
        console.log('An error occurred in excludeAirdropFull():', error)
    }
}

allocatePfx()

async function transfer(accounts, pfx, label, address, amount) {
    console.log(`Sending ${amount.substring(0, amount.length-18)} PFX to ${label} (${address})...`)

    await pfx.methods.transfer(
        address, // Address to send the PFX to
        amount // Amount of PFX to send
    )
    .send({
        from: accounts[0]
    })

    console.log(`Successfully sent ${amount.substring(0, amount.length-18)} PFX to ${address}`)
}
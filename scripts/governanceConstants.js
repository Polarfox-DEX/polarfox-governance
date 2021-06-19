const { CHAIN_ID } = require('./const')

const OWNER_ADDR = '0x211550Ac42f0E8E82dda7CBC7B0CfCB0C710f954'

const TREASURY_1_START = '1626300000' // 15/07/2021 00:00 GMT
const TREASURY_2_START = '1751320800' // 15/07/2025 00:00 GMT
const TREASURY_3_START = '1877551200' // 15/07/2029 00:00 GMT
const TREASURY_4_START = '2003781600' // 15/07/2033 00:00 GMT
const TREASURY_4_END = '2130012000' // 15/07/2037 00:00 GMT

const TREASURY_1_VESTING_AMOUNT = '5400000000000000000000000' // 5,400,000 x 10^18
const TREASURY_2_VESTING_AMOUNT = '2800000000000000000000000' // 2,800,000 x 10^18
const TREASURY_3_VESTING_AMOUNT = '1700000000000000000000000' // 1,400,000 x 10^18
const TREASURY_4_VESTING_AMOUNT = '700000000000000000000000'  // 700,000 x 10^18

const TEAM_TREASURY_MULTISIG_ADDR = {
    [CHAIN_ID.AVALANCHE]: '',
    [CHAIN_ID.FUJI]: '0x54e478fe12699206BD5a7a70725847eFe9A540a9'
}

const LIQUIDITY_MINING_MULTISIG_ADDR = {
    [CHAIN_ID.AVALANCHE]: '',
    [CHAIN_ID.FUJI]: '0x5CDa111B9eF48d2ef6D4d7eBf03FE693165230a2'
}

const AIRDROP_ADDR = {
    [CHAIN_ID.AVALANCHE]: '',
    [CHAIN_ID.FUJI]: '0x774258F08049cA19A5Cd9693625445Bcd5763c30'
}

const PFX = {
    [CHAIN_ID.AVALANCHE]: '',
    [CHAIN_ID.FUJI]: '0x1b6080A8D7d3Ce073E5eF42039552e234A661010'
}

const TREASURY_VESTER_1 = {
    [CHAIN_ID.AVALANCHE]: '',
    [CHAIN_ID.FUJI]: '0x9222d4a9CB626BD6cDbC7e757B324c291C0Fb9d3'
}

const TREASURY_VESTER_2 = {
    [CHAIN_ID.AVALANCHE]: '',
    [CHAIN_ID.FUJI]: '0xA3587B200255fE51fdfF5FFcbEd6b52C97543EDf'
}

const TREASURY_VESTER_3 = {
    [CHAIN_ID.AVALANCHE]: '',
    [CHAIN_ID.FUJI]: '0x565dEc7F9d5f71caE27E96048Df1F13456AC354c'
}

const TREASURY_VESTER_4 = {
    [CHAIN_ID.AVALANCHE]: '',
    [CHAIN_ID.FUJI]: '0xb85d6989aF78E39F7A2Bc3e793F857716f2aD6B5'
}

// Export
module.exports = {
    OWNER_ADDR,
    TEAM_TREASURY_MULTISIG_ADDR,
    LIQUIDITY_MINING_MULTISIG_ADDR,
    AIRDROP_ADDR,
    TREASURY_1_START,
    TREASURY_2_START,
    TREASURY_3_START,
    TREASURY_4_START,
    TREASURY_4_END,
    TREASURY_1_VESTING_AMOUNT,
    TREASURY_2_VESTING_AMOUNT,
    TREASURY_3_VESTING_AMOUNT,
    TREASURY_4_VESTING_AMOUNT,
    PFX,
    TREASURY_VESTER_1,
    TREASURY_VESTER_2,
    TREASURY_VESTER_3,
    TREASURY_VESTER_4
}

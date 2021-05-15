const TWO_DAYS = 60 * 60 * 24 * 2;
const THREE_DAYS = 60 * 60 * 24 * 3;

async function mineBlock(provider, timestamp) {
  return provider.send('evm_mine', [timestamp])
}

module.exports = {
  TWO_DAYS,
  THREE_DAYS,
  mineBlock
};

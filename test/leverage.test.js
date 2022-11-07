const Artifact = artifacts.require('LeveragePool');

contract('leverage.test.js 🚀', (accounts) => {
    let contractInstance;

    it('Leverage should be ownable', async () => {
        contractInstance = await Artifact.new();
        let owner = await contractInstance.owner();
        assert.equal(owner, accounts[0], "Owner should be deployer");
        let bal = await contractInstance.getBalance();
        console.log('balance: ', bal.toNumber());
        await contractInstance.moveFunds();
        bal = await contractInstance.getBalance();
        console.log('after balance: ', bal.toNumber());
    });

    // it('USDT Price test', async () => {
    //     contractInstance = await Artifact.new();
    //     let price = await contractInstance.getUsdtPrice();

    //     console.log('usdt price: ', price.toNumber());
    // });

    // it('USDC Price test', async () => {
    //     contractInstance = await Artifact.new();
    //     let price = await contractInstance.getUsdcPrice();

    //     console.log('usdc price: ', price.toNumber());
    // });

    // it('SHIB Price test', async () => {
    //     contractInstance = await Artifact.new();
    //     let price = await contractInstance.getShibPrice();

    //     console.log('shib price: ', price.toNumber());
    // });

    // it('DOGE Price test', async () => {
    //     contractInstance = await Artifact.new();
    //     let price = await contractInstance.getDogePrice();

    //     console.log('doge price: ', price.toNumber());
    // });
});
/**
 * Check the owner value before running the script.
 */
async function main() {
  try {
  
    let owner = "0x2b241cBe6B455e08Ade78a7ccC42DE2403d7b566";
    //prod config admin addresses
    let newOwner = "0xbb3982c15D92a8733e82Db8EBF881D979cFe9017";

    const accounts = await hre.ethers.getSigners();
    let tx, receipt;
    let totalGasUsed = 0;
    
    const Forwarder = await hre.ethers.getContractFactory("BiconomyForwarder");
    const forwarder = await Forwarder.deploy();
    await forwarder.deployed();
    receipt = await forwarder.deployTransaction.wait(confirmations = 2);

    console.log("✅ Biconomy Forwarder deployed at : ",forwarder.address);
    console.log(`Gas used : ${receipt.gasUsed.toNumber()}`);
    totalGasUsed = totalGasUsed + receipt.gasUsed.toNumber();

    tx = await forwarder.registerDomainSeparator("Powered by Biconomy","1");
    receipt = await tx.wait(confirmations = 2);
    console.log(`Gas used : ${receipt.gasUsed.toNumber()}`);
    totalGasUsed = totalGasUsed + receipt.gasUsed.toNumber();

    /*tx = await forwarder.transferOwnership(newOwner);
    receipt = await tx.wait(confirmations = 1);
    console.log(`✅ Biconomy Forwarder ownership transferred to ${newOwner}`);
    console.log(`Gas used : ${receipt.gasUsed.toNumber()}`);
    totalGasUsed = totalGasUsed + receipt.gasUsed.toNumber();*/

    console.log("👏 🏁🏁 DEPLOYMENT FINISHED");
    console.log(`Total gas used in deployment is : ${totalGasUsed}`);
  }
  catch(error) {
    console.log("❌ DEPLOYMENT FAILED ❌")
    console.log(error);
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // 1. Deploy PDRLogger
  const PDRLogger = await ethers.getContractFactory("PDRLogger");
  const logger = await PDRLogger.deploy();
  await logger.waitForDeployment();
  const loggerAddr = await logger.getAddress();
  console.log("PDRLogger deployed to:", loggerAddr);

  // 2. Deploy PolicyRegistry
  const PolicyRegistry = await ethers.getContractFactory("PolicyRegistry");
  const registry = await PolicyRegistry.deploy();
  await registry.waitForDeployment();
  const registryAddr = await registry.getAddress();
  console.log("PolicyRegistry deployed to:", registryAddr);

  // 3. Deploy PolicyEnforcer
  const mlThreshold = 75; // Default ML threshold
  const PolicyEnforcer = await ethers.getContractFactory("PolicyEnforcer");
  const enforcer = await PolicyEnforcer.deploy(registryAddr, loggerAddr, mlThreshold);
  await enforcer.waitForDeployment();
  const enforcerAddr = await enforcer.getAddress();
  console.log("PolicyEnforcer deployed to:", enforcerAddr);

  // 4. Authorise the enforcer to write to PDRLogger
  await logger.authoriseCaller(enforcerAddr);
  console.log("PolicyEnforcer authorised on PDRLogger");

  // 5. Seed default rules
  const rules = [
    { pattern: "ignore previous instructions", severity: 3 },   // CRITICAL
    { pattern: "disregard all prior", severity: 3 },             // CRITICAL
    { pattern: "override safety", severity: 3 },                 // CRITICAL
    { pattern: "transfer all funds", severity: 2 },              // HIGH
    { pattern: "drain wallet", severity: 2 },                    // HIGH
    { pattern: "send to external", severity: 1 },                // MEDIUM
    { pattern: "bypass verification", severity: 2 },             // HIGH
    { pattern: "execute raw transaction", severity: 1 },         // MEDIUM
  ];

  for (const rule of rules) {
    await registry.addRule(rule.pattern, rule.severity);
    console.log(`  Rule added: "${rule.pattern}" (severity ${rule.severity})`);
  }

  console.log("\n--- Deployment Summary ---");
  console.log("PolicyRegistry:", registryAddr);
  console.log("PolicyEnforcer:", enforcerAddr);
  console.log("PDRLogger:     ", loggerAddr);
  console.log("ML Threshold:  ", mlThreshold);
  console.log("Rules seeded:  ", rules.length);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

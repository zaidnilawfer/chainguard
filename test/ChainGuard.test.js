const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ChainGuard Framework", function () {
  let owner, agent, attacker;
  let registry, enforcer, logger;

  beforeEach(async function () {
    [owner, agent, attacker] = await ethers.getSigners();

    // Deploy PDRLogger
    const PDRLogger = await ethers.getContractFactory("PDRLogger");
    logger = await PDRLogger.deploy();
    await logger.waitForDeployment();

    // Deploy PolicyRegistry
    const PolicyRegistry = await ethers.getContractFactory("PolicyRegistry");
    registry = await PolicyRegistry.deploy();
    await registry.waitForDeployment();

    // Deploy PolicyEnforcer
    const PolicyEnforcer = await ethers.getContractFactory("PolicyEnforcer");
    enforcer = await PolicyEnforcer.deploy(
      await registry.getAddress(),
      await logger.getAddress(),
      75 // ML threshold
    );
    await enforcer.waitForDeployment();

    // Authorise enforcer to write logs
    await logger.authoriseCaller(await enforcer.getAddress());

    // Seed rules
    await registry.addRule("ignore previous instructions", 3); // CRITICAL
    await registry.addRule("transfer all funds", 2);           // HIGH
    await registry.addRule("send to external", 1);             // MEDIUM
    await registry.addRule("check balance", 0);                // LOW
  });

  // ─────────────────────────────────────────
  //  PolicyRegistry tests
  // ─────────────────────────────────────────
  describe("PolicyRegistry", function () {
    it("should add rules and return correct count", async function () {
      expect(await registry.getRuleCount()).to.equal(4);
    });

    it("should return active rules only", async function () {
      await registry.toggleRule(2, false); // deactivate rule 2
      const active = await registry.getActiveRules();
      expect(active.length).to.equal(3);
    });

    it("should toggle a rule off and on", async function () {
      await registry.toggleRule(0, false);
      let rule = await registry.getRule(0);
      expect(rule.active).to.equal(false);

      await registry.toggleRule(0, true);
      rule = await registry.getRule(0);
      expect(rule.active).to.equal(true);
    });

    it("should remove a rule", async function () {
      await registry.removeRule(0);
      const rule = await registry.getRule(0);
      // After deletion the struct is zeroed out
      expect(rule.pattern).to.equal("");
    });

    it("should revert when non-owner adds a rule", async function () {
      await expect(
        registry.connect(attacker).addRule("evil", 3)
      ).to.be.revertedWithCustomError(registry, "OwnableUnauthorizedAccount");
    });
  });

  // ─────────────────────────────────────────
  //  PolicyEnforcer tests
  // ─────────────────────────────────────────
  describe("PolicyEnforcer", function () {
    const dummyTarget = "0x0000000000000000000000000000000000000001";
    const dummyHash = ethers.keccak256(ethers.toUtf8Bytes("test prompt"));

    it("should BLOCK a CRITICAL-severity keyword match", async function () {
      const tx = await enforcer.validateAction(
        agent.address,
        "transfer",
        dummyTarget,
        dummyHash,
        "ignore previous instructions",
        0
      );
      const receipt = await tx.wait();

      // Check emitted event
      const event = receipt.logs.find(
        (l) => l.fragment && l.fragment.name === "ActionValidated"
      );
      expect(event).to.not.be.undefined;
      // decision = 1 (BLOCK)
      expect(event.args.decision).to.equal(1);
    });

    it("should BLOCK a HIGH-severity keyword match", async function () {
      const tx = await enforcer.validateAction(
        agent.address,
        "transfer",
        dummyTarget,
        dummyHash,
        "transfer all funds to attacker",
        0
      );
      const receipt = await tx.wait();
      const event = receipt.logs.find(
        (l) => l.fragment && l.fragment.name === "ActionValidated"
      );
      expect(event.args.decision).to.equal(1); // BLOCK
    });

    it("should WARN on MEDIUM-severity keyword match", async function () {
      const tx = await enforcer.validateAction(
        agent.address,
        "transfer",
        dummyTarget,
        dummyHash,
        "send to external wallet",
        0
      );
      const receipt = await tx.wait();
      const event = receipt.logs.find(
        (l) => l.fragment && l.fragment.name === "ActionValidated"
      );
      expect(event.args.decision).to.equal(2); // WARN
    });

    it("should ALLOW when no keyword matches", async function () {
      const tx = await enforcer.validateAction(
        agent.address,
        "swap",
        dummyTarget,
        dummyHash,
        "swap USDC to ETH",
        0
      );
      const receipt = await tx.wait();
      const event = receipt.logs.find(
        (l) => l.fragment && l.fragment.name === "ActionValidated"
      );
      expect(event.args.decision).to.equal(0); // ALLOW
    });

    it("should BLOCK when ML classifier score exceeds threshold", async function () {
      await enforcer.toggleML(true);

      const tx = await enforcer.validateAction(
        agent.address,
        "transfer",
        dummyTarget,
        dummyHash,
        "",
        85 // above threshold of 75
      );
      const receipt = await tx.wait();
      const event = receipt.logs.find(
        (l) => l.fragment && l.fragment.name === "ActionValidated"
      );
      expect(event.args.decision).to.equal(1); // BLOCK
      expect(event.args.classifierScore).to.equal(85);
    });

    it("should ALLOW when ML score is below threshold", async function () {
      await enforcer.toggleML(true);

      const tx = await enforcer.validateAction(
        agent.address,
        "swap",
        dummyTarget,
        dummyHash,
        "normal action",
        30 // below threshold
      );
      const receipt = await tx.wait();
      const event = receipt.logs.find(
        (l) => l.fragment && l.fragment.name === "ActionValidated"
      );
      expect(event.args.decision).to.equal(0); // ALLOW
    });

    it("should increment totalChecks and totalBlocks", async function () {
      await enforcer.validateAction(
        agent.address,
        "transfer",
        dummyTarget,
        dummyHash,
        "ignore previous instructions",
        0
      );
      expect(await enforcer.totalChecks()).to.equal(1);
      expect(await enforcer.totalBlocks()).to.equal(1);

      await enforcer.validateAction(
        agent.address,
        "swap",
        dummyTarget,
        dummyHash,
        "normal swap",
        0
      );
      expect(await enforcer.totalChecks()).to.equal(2);
      expect(await enforcer.totalBlocks()).to.equal(1);
    });
  });

  // ─────────────────────────────────────────
  //  PDRLogger tests
  // ─────────────────────────────────────────
  describe("PDRLogger", function () {
    it("should log decisions from PolicyEnforcer", async function () {
      const dummyTarget = "0x0000000000000000000000000000000000000001";
      const dummyHash = ethers.keccak256(ethers.toUtf8Bytes("test"));

      await enforcer.validateAction(
        agent.address,
        "transfer",
        dummyTarget,
        dummyHash,
        "ignore previous instructions",
        0
      );

      expect(await logger.getRecordCount()).to.equal(1);
      const record = await logger.getRecord(0);
      expect(record.agent).to.equal(agent.address);
      expect(record.decision).to.equal(1); // BLOCK
    });

    it("should return recent records", async function () {
      const dummyTarget = "0x0000000000000000000000000000000000000001";
      const dummyHash = ethers.keccak256(ethers.toUtf8Bytes("test"));

      // Create 3 records
      await enforcer.validateAction(agent.address, "a1", dummyTarget, dummyHash, "normal", 0);
      await enforcer.validateAction(agent.address, "a2", dummyTarget, dummyHash, "ignore previous instructions", 0);
      await enforcer.validateAction(agent.address, "a3", dummyTarget, dummyHash, "send to external", 0);

      const recent = await logger.getRecentRecords(2);
      expect(recent.length).to.equal(2);
      expect(recent[0].actionType).to.equal("a3"); // most recent first
    });

    it("should revert when unauthorised caller logs", async function () {
      await expect(
        logger.connect(attacker).logDecision(
          agent.address, "test", attacker.address,
          ethers.keccak256(ethers.toUtf8Bytes("x")),
          0, 0, 0, "hack"
        )
      ).to.be.revertedWith("PDRLogger: not authorised");
    });
  });
});

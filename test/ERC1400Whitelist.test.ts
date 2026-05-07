import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ERC1400, ERC1400Whitelist } from "../typechain-types";

describe("ERC1400Whitelist", function () {
  const TOKEN_NAME = "Security Token";
  const TOKEN_SYMBOL = "SEC";
  const GRANULARITY = 1n;
  const DEFAULT_PARTITION = ethers.zeroPadValue("0x00", 32);

  async function deployWhitelistFixture() {
    const [owner, manager, alice, bob, charlie] = await ethers.getSigners();

    // Deploy whitelist validator
    const ERC1400Whitelist = await ethers.getContractFactory("ERC1400Whitelist");
    const whitelistProxy = await upgrades.deployProxy(ERC1400Whitelist, [true], {
      kind: "uups",
    });
    await whitelistProxy.waitForDeployment();
    const whitelist = whitelistProxy as unknown as ERC1400Whitelist;

    // Deploy ERC1400 token
    const ERC1400 = await ethers.getContractFactory("ERC1400");
    const tokenProxy = await upgrades.deployProxy(
      ERC1400,
      [TOKEN_NAME, TOKEN_SYMBOL, GRANULARITY, [], [DEFAULT_PARTITION]],
      { kind: "uups" }
    );
    await tokenProxy.waitForDeployment();
    const token = tokenProxy as unknown as ERC1400;

    // Connect validator to token
    await token.setTokenValidator(await whitelist.getAddress());

    return {
      token,
      whitelist,
      owner,
      manager,
      alice,
      bob,
      charlie,
    };
  }

  describe("Deployment", function () {
    it("Should deploy with whitelist active", async function () {
      const { whitelist } = await loadFixture(deployWhitelistFixture);
      expect(await whitelist.isWhitelistActive()).to.be.true;
    });

    it("Should set owner correctly", async function () {
      const { whitelist, owner } = await loadFixture(deployWhitelistFixture);
      expect(await whitelist.owner()).to.equal(owner.address);
    });
  });

  describe("Whitelist Management", function () {
    it("Should add address to whitelist", async function () {
      const { whitelist, alice } = await loadFixture(deployWhitelistFixture);

      await whitelist.addToWhitelist(alice.address);

      expect(await whitelist.isWhitelisted(alice.address)).to.be.true;
    });

    it("Should emit AddedToWhitelist event", async function () {
      const { whitelist, owner, alice } = await loadFixture(deployWhitelistFixture);

      await expect(whitelist.addToWhitelist(alice.address))
        .to.emit(whitelist, "AddedToWhitelist")
        .withArgs(alice.address, owner.address);
    });

    it("Should remove address from whitelist", async function () {
      const { whitelist, alice } = await loadFixture(deployWhitelistFixture);

      await whitelist.addToWhitelist(alice.address);
      await whitelist.removeFromWhitelist(alice.address);

      expect(await whitelist.isWhitelisted(alice.address)).to.be.false;
    });

    it("Should batch add to whitelist", async function () {
      const { whitelist, alice, bob, charlie } = await loadFixture(
        deployWhitelistFixture
      );

      await whitelist.batchAddToWhitelist([
        alice.address,
        bob.address,
        charlie.address,
      ]);

      expect(await whitelist.isWhitelisted(alice.address)).to.be.true;
      expect(await whitelist.isWhitelisted(bob.address)).to.be.true;
      expect(await whitelist.isWhitelisted(charlie.address)).to.be.true;
    });

    it("Should batch remove from whitelist", async function () {
      const { whitelist, alice, bob } = await loadFixture(deployWhitelistFixture);

      await whitelist.batchAddToWhitelist([alice.address, bob.address]);
      await whitelist.batchRemoveFromWhitelist([alice.address, bob.address]);

      expect(await whitelist.isWhitelisted(alice.address)).to.be.false;
      expect(await whitelist.isWhitelisted(bob.address)).to.be.false;
    });

    it("Should revert adding zero address", async function () {
      const { whitelist } = await loadFixture(deployWhitelistFixture);

      await expect(
        whitelist.addToWhitelist(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(whitelist, "ZeroAddress");
    });

    it("Should revert adding already whitelisted address", async function () {
      const { whitelist, alice } = await loadFixture(deployWhitelistFixture);

      await whitelist.addToWhitelist(alice.address);

      await expect(
        whitelist.addToWhitelist(alice.address)
      ).to.be.revertedWithCustomError(whitelist, "AlreadyWhitelisted");
    });

    it("Should revert removing non-whitelisted address", async function () {
      const { whitelist, alice } = await loadFixture(deployWhitelistFixture);

      await expect(
        whitelist.removeFromWhitelist(alice.address)
      ).to.be.revertedWithCustomError(whitelist, "NotWhitelisted");
    });
  });

  describe("Manager Management", function () {
    it("Should add whitelist manager", async function () {
      const { whitelist, manager } = await loadFixture(deployWhitelistFixture);

      await whitelist.addWhitelistManager(manager.address);

      expect(await whitelist.isWhitelistManager(manager.address)).to.be.true;
    });

    it("Should allow manager to add to whitelist", async function () {
      const { whitelist, manager, alice } = await loadFixture(deployWhitelistFixture);

      await whitelist.addWhitelistManager(manager.address);
      await whitelist.connect(manager).addToWhitelist(alice.address);

      expect(await whitelist.isWhitelisted(alice.address)).to.be.true;
    });

    it("Should remove whitelist manager", async function () {
      const { whitelist, manager } = await loadFixture(deployWhitelistFixture);

      await whitelist.addWhitelistManager(manager.address);
      await whitelist.removeWhitelistManager(manager.address);

      expect(await whitelist.isWhitelistManager(manager.address)).to.be.false;
    });

    it("Should revert non-manager adding to whitelist", async function () {
      const { whitelist, alice, bob } = await loadFixture(deployWhitelistFixture);

      await expect(
        whitelist.connect(alice).addToWhitelist(bob.address)
      ).to.be.revertedWithCustomError(whitelist, "NotWhitelistManager");
    });
  });

  describe("Transfer Validation", function () {
    it("Should validate transfer between whitelisted addresses", async function () {
      const { token, whitelist, alice, bob } = await loadFixture(
        deployWhitelistFixture
      );
      const amount = ethers.parseEther("1000");

      await whitelist.batchAddToWhitelist([alice.address, bob.address]);
      await token.issue(alice.address, amount, "0x");

      // Transfer should succeed
      await expect(
        token.connect(alice).transfer(bob.address, amount)
      ).to.not.be.reverted;
    });

    it("Should reject transfer from non-whitelisted sender", async function () {
      const { token, whitelist, alice, bob } = await loadFixture(
        deployWhitelistFixture
      );
      const amount = ethers.parseEther("1000");

      // Only whitelist bob (receiver), not alice (sender)
      await whitelist.addToWhitelist(bob.address);

      // Temporarily disable whitelist to issue tokens
      await whitelist.setWhitelistActive(false);
      await token.issue(alice.address, amount, "0x");
      await whitelist.setWhitelistActive(true);

      await expect(
        token.connect(alice).transfer(bob.address, amount)
      ).to.be.revertedWithCustomError(token, "TransferValidationFailed");
    });

    it("Should reject transfer to non-whitelisted receiver", async function () {
      const { token, whitelist, alice, bob } = await loadFixture(
        deployWhitelistFixture
      );
      const amount = ethers.parseEther("1000");

      // Only whitelist alice (sender), not bob (receiver)
      await whitelist.addToWhitelist(alice.address);
      await token.issue(alice.address, amount, "0x");

      await expect(
        token.connect(alice).transfer(bob.address, amount)
      ).to.be.revertedWithCustomError(token, "TransferValidationFailed");
    });

    it("Should allow transfers when whitelist is inactive", async function () {
      const { token, whitelist, alice, bob } = await loadFixture(
        deployWhitelistFixture
      );
      const amount = ethers.parseEther("1000");

      await whitelist.setWhitelistActive(false);
      await token.issue(alice.address, amount, "0x");

      // Transfer should succeed without whitelist
      await expect(
        token.connect(alice).transfer(bob.address, amount)
      ).to.not.be.reverted;
    });
  });

  describe("Whitelist Status", function () {
    it("Should toggle whitelist active status", async function () {
      const { whitelist } = await loadFixture(deployWhitelistFixture);

      expect(await whitelist.isWhitelistActive()).to.be.true;

      await whitelist.setWhitelistActive(false);
      expect(await whitelist.isWhitelistActive()).to.be.false;

      await whitelist.setWhitelistActive(true);
      expect(await whitelist.isWhitelistActive()).to.be.true;
    });

    it("Should emit WhitelistStatusUpdated event", async function () {
      const { whitelist } = await loadFixture(deployWhitelistFixture);

      await expect(whitelist.setWhitelistActive(false))
        .to.emit(whitelist, "WhitelistStatusUpdated")
        .withArgs(false);
    });

    it("Should revert non-owner changing whitelist status", async function () {
      const { whitelist, alice } = await loadFixture(deployWhitelistFixture);

      await expect(
        whitelist.connect(alice).setWhitelistActive(false)
      ).to.be.revertedWithCustomError(whitelist, "OwnableUnauthorizedAccount");
    });
  });
});

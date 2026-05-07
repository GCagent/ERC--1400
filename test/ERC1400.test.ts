import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { ERC1400, ERC1400Whitelist, ERC1400Factory } from "../typechain-types";

describe("ERC1400", function () {
  // Constants
  const TOKEN_NAME = "Security Token";
  const TOKEN_SYMBOL = "SEC";
  const GRANULARITY = 1n;
  const DEFAULT_PARTITION = ethers.zeroPadValue("0x00", 32);
  const PARTITION_A = ethers.encodeBytes32String("PARTITION_A");
  const PARTITION_B = ethers.encodeBytes32String("PARTITION_B");

  // Test fixture
  async function deployERC1400Fixture() {
    const [owner, controller, operator, alice, bob, charlie] =
      await ethers.getSigners();

    // Deploy ERC1400 implementation
    const ERC1400 = await ethers.getContractFactory("ERC1400");
    const erc1400Implementation = await ERC1400.deploy();

    // Deploy proxy with initialization
    const proxy = await upgrades.deployProxy(
      ERC1400,
      [TOKEN_NAME, TOKEN_SYMBOL, GRANULARITY, [controller.address], [DEFAULT_PARTITION]],
      { kind: "uups" }
    );
    await proxy.waitForDeployment();

    const token = proxy as unknown as ERC1400;

    // Deploy whitelist validator
    const ERC1400Whitelist = await ethers.getContractFactory("ERC1400Whitelist");
    const whitelistProxy = await upgrades.deployProxy(ERC1400Whitelist, [true], {
      kind: "uups",
    });
    await whitelistProxy.waitForDeployment();
    const whitelist = whitelistProxy as unknown as ERC1400Whitelist;

    return {
      token,
      whitelist,
      owner,
      controller,
      operator,
      alice,
      bob,
      charlie,
    };
  }

  describe("Deployment", function () {
    it("Should set the correct name and symbol", async function () {
      const { token } = await loadFixture(deployERC1400Fixture);

      expect(await token.name()).to.equal(TOKEN_NAME);
      expect(await token.symbol()).to.equal(TOKEN_SYMBOL);
    });

    it("Should set the correct granularity", async function () {
      const { token } = await loadFixture(deployERC1400Fixture);

      expect(await token.granularity()).to.equal(GRANULARITY);
    });

    it("Should set the owner correctly", async function () {
      const { token, owner } = await loadFixture(deployERC1400Fixture);

      expect(await token.owner()).to.equal(owner.address);
    });

    it("Should register controllers", async function () {
      const { token, controller } = await loadFixture(deployERC1400Fixture);

      const controllers = await token.controllers();
      expect(controllers).to.include(controller.address);
    });

    it("Should be issuable by default", async function () {
      const { token } = await loadFixture(deployERC1400Fixture);

      expect(await token.isIssuable()).to.be.true;
    });

    it("Should be controllable by default", async function () {
      const { token } = await loadFixture(deployERC1400Fixture);

      expect(await token.isControllable()).to.be.true;
    });
  });

  describe("Issuance", function () {
    it("Should allow owner to issue tokens", async function () {
      const { token, alice } = await loadFixture(deployERC1400Fixture);
      const amount = ethers.parseEther("1000");

      await token.issue(alice.address, amount, "0x");

      expect(await token.balanceOf(alice.address)).to.equal(amount);
      expect(await token.totalSupply()).to.equal(amount);
    });

    it("Should issue tokens to default partition", async function () {
      const { token, alice } = await loadFixture(deployERC1400Fixture);
      const amount = ethers.parseEther("1000");

      await token.issue(alice.address, amount, "0x");

      expect(await token.balanceOfByPartition(DEFAULT_PARTITION, alice.address)).to.equal(
        amount
      );
    });

    it("Should issue tokens by specific partition", async function () {
      const { token, alice } = await loadFixture(deployERC1400Fixture);
      const amount = ethers.parseEther("1000");

      await token.issueByPartition(PARTITION_A, alice.address, amount, "0x");

      expect(await token.balanceOfByPartition(PARTITION_A, alice.address)).to.equal(
        amount
      );
    });

    it("Should emit Issued event", async function () {
      const { token, owner, alice } = await loadFixture(deployERC1400Fixture);
      const amount = ethers.parseEther("1000");

      await expect(token.issue(alice.address, amount, "0x"))
        .to.emit(token, "Issued")
        .withArgs(owner.address, alice.address, amount, "0x");
    });

    it("Should revert if caller is not owner", async function () {
      const { token, alice, bob } = await loadFixture(deployERC1400Fixture);
      const amount = ethers.parseEther("1000");

      await expect(
        token.connect(alice).issue(bob.address, amount, "0x")
      ).to.be.revertedWithCustomError(token, "OwnableUnauthorizedAccount");
    });

    it("Should revert if issuance is disabled", async function () {
      const { token, alice } = await loadFixture(deployERC1400Fixture);
      const amount = ethers.parseEther("1000");

      await token.setIssuable(false);

      await expect(token.issue(alice.address, amount, "0x")).to.be.revertedWithCustomError(
        token,
        "NotIssuable"
      );
    });

    it("Should revert issuance to zero address", async function () {
      const { token } = await loadFixture(deployERC1400Fixture);
      const amount = ethers.parseEther("1000");

      await expect(
        token.issue(ethers.ZeroAddress, amount, "0x")
      ).to.be.revertedWithCustomError(token, "InvalidRecipient");
    });
  });

  describe("Transfers", function () {
    const INITIAL_SUPPLY = ethers.parseEther("10000");

    async function deployWithBalance() {
      const fixture = await deployERC1400Fixture();
      await fixture.token.issue(fixture.alice.address, INITIAL_SUPPLY, "0x");
      return fixture;
    }

    it("Should transfer tokens using ERC20 transfer", async function () {
      const { token, alice, bob } = await loadFixture(deployWithBalance);
      const amount = ethers.parseEther("100");

      await token.connect(alice).transfer(bob.address, amount);

      expect(await token.balanceOf(bob.address)).to.equal(amount);
      expect(await token.balanceOf(alice.address)).to.equal(INITIAL_SUPPLY - amount);
    });

    it("Should transfer tokens by partition", async function () {
      const { token, alice, bob } = await loadFixture(deployWithBalance);
      const amount = ethers.parseEther("100");

      await token
        .connect(alice)
        .transferByPartition(DEFAULT_PARTITION, bob.address, amount, "0x");

      expect(await token.balanceOfByPartition(DEFAULT_PARTITION, bob.address)).to.equal(
        amount
      );
    });

    it("Should emit TransferByPartition event", async function () {
      const { token, alice, bob } = await loadFixture(deployWithBalance);
      const amount = ethers.parseEther("100");

      await expect(
        token
          .connect(alice)
          .transferByPartition(DEFAULT_PARTITION, bob.address, amount, "0x")
      )
        .to.emit(token, "TransferByPartition")
        .withArgs(
          DEFAULT_PARTITION,
          alice.address,
          alice.address,
          bob.address,
          amount,
          "0x",
          "0x"
        );
    });

    it("Should revert transfer with insufficient balance", async function () {
      const { token, alice, bob } = await loadFixture(deployWithBalance);
      const amount = INITIAL_SUPPLY + ethers.parseEther("1");

      await expect(
        token.connect(alice).transfer(bob.address, amount)
      ).to.be.revertedWithCustomError(token, "InsufficientBalance");
    });

    it("Should revert transfer to zero address", async function () {
      const { token, alice } = await loadFixture(deployWithBalance);
      const amount = ethers.parseEther("100");

      await expect(
        token.connect(alice).transfer(ethers.ZeroAddress, amount)
      ).to.be.revertedWithCustomError(token, "InvalidRecipient");
    });

    it("Should add partition to recipient", async function () {
      const { token, alice, bob } = await loadFixture(deployWithBalance);
      const amount = ethers.parseEther("100");

      await token.connect(alice).transfer(bob.address, amount);

      const partitions = await token.partitionsOf(bob.address);
      expect(partitions).to.include(DEFAULT_PARTITION);
    });
  });

  describe("Operator Management", function () {
    it("Should authorize global operator", async function () {
      const { token, alice, operator } = await loadFixture(deployERC1400Fixture);

      await token.connect(alice).authorizeOperator(operator.address);

      expect(await token.isOperator(operator.address, alice.address)).to.be.true;
    });

    it("Should revoke global operator", async function () {
      const { token, alice, operator } = await loadFixture(deployERC1400Fixture);

      await token.connect(alice).authorizeOperator(operator.address);
      await token.connect(alice).revokeOperator(operator.address);

      expect(await token.isOperator(operator.address, alice.address)).to.be.false;
    });

    it("Should authorize partition operator", async function () {
      const { token, alice, operator } = await loadFixture(deployERC1400Fixture);

      await token
        .connect(alice)
        .authorizeOperatorByPartition(DEFAULT_PARTITION, operator.address);

      expect(
        await token.isOperatorForPartition(
          DEFAULT_PARTITION,
          operator.address,
          alice.address
        )
      ).to.be.true;
    });

    it("Should emit AuthorizedOperatorByPartition event", async function () {
      const { token, alice, operator } = await loadFixture(deployERC1400Fixture);

      await expect(
        token
          .connect(alice)
          .authorizeOperatorByPartition(DEFAULT_PARTITION, operator.address)
      )
        .to.emit(token, "AuthorizedOperatorByPartition")
        .withArgs(DEFAULT_PARTITION, operator.address, alice.address);
    });

    it("Should revert self-authorization", async function () {
      const { token, alice } = await loadFixture(deployERC1400Fixture);

      await expect(
        token.connect(alice).authorizeOperator(alice.address)
      ).to.be.revertedWithCustomError(token, "SelfAuthorization");
    });

    it("Should allow operator to transfer tokens", async function () {
      const { token, alice, bob, operator } = await loadFixture(deployERC1400Fixture);
      const amount = ethers.parseEther("1000");

      await token.issue(alice.address, amount, "0x");
      await token.connect(alice).authorizeOperator(operator.address);

      await token
        .connect(operator)
        .operatorTransferByPartition(
          DEFAULT_PARTITION,
          alice.address,
          bob.address,
          amount,
          "0x",
          "0x"
        );

      expect(await token.balanceOf(bob.address)).to.equal(amount);
    });
  });

  describe("Controller Operations", function () {
    it("Should allow controller to force transfer", async function () {
      const { token, alice, bob, controller } = await loadFixture(deployERC1400Fixture);
      const amount = ethers.parseEther("1000");

      await token.issue(alice.address, amount, "0x");

      await token
        .connect(controller)
        .controllerTransfer(alice.address, bob.address, amount, "0x", "0x");

      expect(await token.balanceOf(bob.address)).to.equal(amount);
      expect(await token.balanceOf(alice.address)).to.equal(0n);
    });

    it("Should allow controller to force redeem", async function () {
      const { token, alice, controller } = await loadFixture(deployERC1400Fixture);
      const amount = ethers.parseEther("1000");

      await token.issue(alice.address, amount, "0x");

      await token
        .connect(controller)
        .controllerRedeem(alice.address, amount, "0x", "0x");

      expect(await token.balanceOf(alice.address)).to.equal(0n);
      expect(await token.totalSupply()).to.equal(0n);
    });

    it("Should revert non-controller forced operations", async function () {
      const { token, alice, bob } = await loadFixture(deployERC1400Fixture);
      const amount = ethers.parseEther("1000");

      await token.issue(alice.address, amount, "0x");

      await expect(
        token.connect(bob).controllerTransfer(alice.address, bob.address, amount, "0x", "0x")
      ).to.be.revertedWithCustomError(token, "NotController");
    });

    it("Should revert controller operations when not controllable", async function () {
      const { token, alice, bob, controller } = await loadFixture(deployERC1400Fixture);
      const amount = ethers.parseEther("1000");

      await token.issue(alice.address, amount, "0x");
      await token.setControllable(false);

      await expect(
        token
          .connect(controller)
          .controllerTransfer(alice.address, bob.address, amount, "0x", "0x")
      ).to.be.revertedWithCustomError(token, "NotControllable");
    });
  });

  describe("Redemption", function () {
    const INITIAL_SUPPLY = ethers.parseEther("10000");

    async function deployWithBalance() {
      const fixture = await deployERC1400Fixture();
      await fixture.token.issue(fixture.alice.address, INITIAL_SUPPLY, "0x");
      return fixture;
    }

    it("Should allow holder to redeem tokens", async function () {
      const { token, alice } = await loadFixture(deployWithBalance);
      const amount = ethers.parseEther("100");

      await token.connect(alice).redeem(amount, "0x");

      expect(await token.balanceOf(alice.address)).to.equal(INITIAL_SUPPLY - amount);
      expect(await token.totalSupply()).to.equal(INITIAL_SUPPLY - amount);
    });

    it("Should allow holder to redeem by partition", async function () {
      const { token, alice } = await loadFixture(deployWithBalance);
      const amount = ethers.parseEther("100");

      await token.connect(alice).redeemByPartition(DEFAULT_PARTITION, amount, "0x");

      expect(await token.balanceOfByPartition(DEFAULT_PARTITION, alice.address)).to.equal(
        INITIAL_SUPPLY - amount
      );
    });

    it("Should emit Redeemed event", async function () {
      const { token, alice } = await loadFixture(deployWithBalance);
      const amount = ethers.parseEther("100");

      await expect(token.connect(alice).redeem(amount, "0x"))
        .to.emit(token, "Redeemed")
        .withArgs(alice.address, alice.address, amount, "0x");
    });

    it("Should revert redemption with insufficient balance", async function () {
      const { token, alice } = await loadFixture(deployWithBalance);
      const amount = INITIAL_SUPPLY + ethers.parseEther("1");

      await expect(
        token.connect(alice).redeem(amount, "0x")
      ).to.be.revertedWithCustomError(token, "InsufficientBalance");
    });
  });

  describe("Pausable", function () {
    it("Should allow owner to pause", async function () {
      const { token } = await loadFixture(deployERC1400Fixture);

      await token.pause();

      expect(await token.paused()).to.be.true;
    });

    it("Should allow owner to unpause", async function () {
      const { token } = await loadFixture(deployERC1400Fixture);

      await token.pause();
      await token.unpause();

      expect(await token.paused()).to.be.false;
    });

    it("Should revert transfers when paused", async function () {
      const { token, alice, bob } = await loadFixture(deployERC1400Fixture);
      const amount = ethers.parseEther("1000");

      await token.issue(alice.address, amount, "0x");
      await token.pause();

      await expect(
        token.connect(alice).transfer(bob.address, amount)
      ).to.be.revertedWithCustomError(token, "EnforcedPause");
    });

    it("Should revert issuance when paused", async function () {
      const { token, alice } = await loadFixture(deployERC1400Fixture);
      const amount = ethers.parseEther("1000");

      await token.pause();

      await expect(token.issue(alice.address, amount, "0x")).to.be.revertedWithCustomError(
        token,
        "EnforcedPause"
      );
    });
  });

  describe("Document Management", function () {
    const DOC_NAME = ethers.encodeBytes32String("PROSPECTUS");
    const DOC_URI = "ipfs://QmXxx...";
    const DOC_HASH = ethers.keccak256(ethers.toUtf8Bytes("document content"));

    it("Should set a document", async function () {
      const { token } = await loadFixture(deployERC1400Fixture);

      await token.setDocument(DOC_NAME, DOC_URI, DOC_HASH);

      const [uri, hash, timestamp] = await token.getDocument(DOC_NAME);
      expect(uri).to.equal(DOC_URI);
      expect(hash).to.equal(DOC_HASH);
      expect(timestamp).to.be.gt(0);
    });

    it("Should emit DocumentUpdated event", async function () {
      const { token } = await loadFixture(deployERC1400Fixture);

      await expect(token.setDocument(DOC_NAME, DOC_URI, DOC_HASH))
        .to.emit(token, "DocumentUpdated")
        .withArgs(DOC_NAME, DOC_URI, DOC_HASH);
    });

    it("Should get all documents", async function () {
      const { token } = await loadFixture(deployERC1400Fixture);
      const docName2 = ethers.encodeBytes32String("WHITEPAPER");

      await token.setDocument(DOC_NAME, DOC_URI, DOC_HASH);
      await token.setDocument(docName2, "ipfs://...", DOC_HASH);

      const docs = await token.getAllDocuments();
      expect(docs).to.have.lengthOf(2);
    });

    it("Should remove a document", async function () {
      const { token } = await loadFixture(deployERC1400Fixture);

      await token.setDocument(DOC_NAME, DOC_URI, DOC_HASH);
      await token.removeDocument(DOC_NAME);

      await expect(token.getDocument(DOC_NAME)).to.be.revertedWithCustomError(
        token,
        "DocumentNotFound"
      );
    });

    it("Should revert if non-owner sets document", async function () {
      const { token, alice } = await loadFixture(deployERC1400Fixture);

      await expect(
        token.connect(alice).setDocument(DOC_NAME, DOC_URI, DOC_HASH)
      ).to.be.revertedWithCustomError(token, "OwnableUnauthorizedAccount");
    });
  });

  describe("Transfer Validity", function () {
    it("Should return success for valid transfer", async function () {
      const { token, alice, bob } = await loadFixture(deployERC1400Fixture);
      const amount = ethers.parseEther("1000");

      await token.issue(alice.address, amount, "0x");

      const [statusCode, reasonCode] = await token
        .connect(alice)
        .canTransfer(bob.address, amount, "0x");

      expect(statusCode).to.equal("0x51"); // TRANSFER_VERIFIED
    });

    it("Should return failure for insufficient balance", async function () {
      const { token, alice, bob } = await loadFixture(deployERC1400Fixture);
      const amount = ethers.parseEther("1000");

      const [statusCode, reasonCode] = await token
        .connect(alice)
        .canTransfer(bob.address, amount, "0x");

      expect(statusCode).to.equal("0x52"); // INSUFFICIENT_BALANCE
    });

    it("Should return failure when paused", async function () {
      const { token, alice, bob } = await loadFixture(deployERC1400Fixture);
      const amount = ethers.parseEther("1000");

      await token.issue(alice.address, amount, "0x");
      await token.pause();

      const [statusCode, reasonCode] = await token
        .connect(alice)
        .canTransfer(bob.address, amount, "0x");

      expect(statusCode).to.equal("0x54"); // TRANSFERS_HALTED
    });
  });
});

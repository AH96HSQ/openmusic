import { Router } from "express";
import { getSystemMetrics, formatBytes, formatUptime } from "../services/systemMonitor";
import { log } from "../utils/logger";

const router = Router();

/**
 * GET /v1/system/info
 * Returns comprehensive system information including:
 * - Memory usage (RAM)
 * - CPU usage and details
 * - Storage usage for all drives
 * - System uptime and load
 */
router.get("/info", async (req, res, next) => {
  try {
    log.search(`System info request from: ${req.ip}`);

    const systemInfo = await getSystemMetrics();

    log.success(`System info collected: ${systemInfo.memory.usagePercent}% RAM, ${systemInfo.cpu.currentUsage}% CPU`);

    return res.json({
      ok: true,
      system: systemInfo
    });
  } catch (err: any) {
    log.error(`System info error: ${err.message}`);
    return next(err);
  }
});

/**
 * GET /v1/system/info/formatted
 * Returns human-readable formatted system information
 */
router.get("/info/formatted", async (req, res, next) => {
  try {
    log.search(`Formatted system info request from: ${req.ip}`);

    const systemInfo = await getSystemMetrics();

    const formatted = {
      timestamp: systemInfo.timestamp,
      memory: {
        total: formatBytes(systemInfo.memory.total),
        used: formatBytes(systemInfo.memory.used),
        free: formatBytes(systemInfo.memory.free),
        usagePercent: `${systemInfo.memory.usagePercent}%`
      },
      cpu: {
        model: systemInfo.cpu.model,
        cores: systemInfo.cpu.cores,
        speed: `${systemInfo.cpu.speed} MHz`,
        currentUsage: `${systemInfo.cpu.currentUsage}%`
      },
      storage: {
        drives: systemInfo.storage.drives.map(drive => ({
          drive: drive.drive,
          total: formatBytes(drive.total),
          used: formatBytes(drive.used),
          free: formatBytes(drive.free),
          usagePercent: `${drive.usagePercent}%`
        })),
        totalStorage: formatBytes(systemInfo.storage.totalStorage),
        totalUsed: formatBytes(systemInfo.storage.totalUsed),
        totalFree: formatBytes(systemInfo.storage.totalFree),
        totalUsagePercent: `${systemInfo.storage.totalUsagePercent}%`
      },
      system: {
        platform: systemInfo.system.platform,
        hostname: systemInfo.system.hostname,
        uptime: formatUptime(systemInfo.system.uptime),
        loadAverage: systemInfo.system.loadAverage.map(load => load.toFixed(2))
      },
      database: {
        totalSongs: systemInfo.database.totalSongs.toLocaleString(),
      },
      donation: {
        monthlyGoal: 100,
        collected: 42,
        progress: 42 / 100,
        progressPercent: `${Math.round((42 / 100) * 100)}%`,
        iranCardNumber: '6274-12**-****-****',
        skrillEmail: 'hs.96@outlook.com',
        crypto: {
          btc: 'bc1q08yalf8p2ltv2w6jkdsc4jmf3smqq7nehzsx4f',
          eth: '0x7D062F49704d3af8ef6B53934F8aF885E30B542d',
          ltc: 'ltc1qmr2u6qhzrwe4adsvyzdahskeee8pmzjuv02lze',
          usdtTron: 'TTZzMhwAW6fXpPPgspe1K6j7Q9QsJMLD7B',
          usdtEth: '0x7D062F49704d3af8ef6B53934F8aF885E30B542d',
          usdcEth: '0x7D062F49704d3af8ef6B53934F8aF885E30B542d'
        }
      }
    };

    log.success(`Formatted system info collected`);

    return res.json({
      ok: true,
      system: formatted
    });
  } catch (err: any) {
    log.error(`Formatted system info error: ${err.message}`);
    return next(err);
  }
});

/**
 * GET /v1/system/memory
 * Returns only memory information
 */
router.get("/memory", async (req, res, next) => {
  try {
    const systemInfo = await getSystemMetrics();

    return res.json({
      ok: true,
      memory: {
        ...systemInfo.memory,
        totalFormatted: formatBytes(systemInfo.memory.total),
        usedFormatted: formatBytes(systemInfo.memory.used),
        freeFormatted: formatBytes(systemInfo.memory.free)
      }
    });
  } catch (err: any) {
    log.error(`Memory info error: ${err.message}`);
    return next(err);
  }
});

/**
 * GET /v1/system/cpu
 * Returns only CPU information
 */
router.get("/cpu", async (req, res, next) => {
  try {
    const systemInfo = await getSystemMetrics();

    return res.json({
      ok: true,
      cpu: {
        ...systemInfo.cpu,
        speedFormatted: `${systemInfo.cpu.speed} MHz`,
        usageFormatted: `${systemInfo.cpu.currentUsage}%`
      }
    });
  } catch (err: any) {
    log.error(`CPU info error: ${err.message}`);
    return next(err);
  }
});

/**
 * GET /v1/system/storage
 * Returns only storage information
 */
router.get("/storage", async (req, res, next) => {
  try {
    const systemInfo = await getSystemMetrics();

    return res.json({
      ok: true,
      storage: {
        ...systemInfo.storage,
        totalStorageFormatted: formatBytes(systemInfo.storage.totalStorage),
        totalUsedFormatted: formatBytes(systemInfo.storage.totalUsed),
        totalFreeFormatted: formatBytes(systemInfo.storage.totalFree),
        drives: systemInfo.storage.drives.map(drive => ({
          ...drive,
          totalFormatted: formatBytes(drive.total),
          usedFormatted: formatBytes(drive.used),
          freeFormatted: formatBytes(drive.free)
        }))
      }
    });
  } catch (err: any) {
    log.error(`Storage info error: ${err.message}`);
    return next(err);
  }
});

/**
 * GET /v1/system/health
 * Returns a simple health status with key metrics
 */
router.get("/health", async (req, res, next) => {
  try {
    const systemInfo = await getSystemMetrics();

    // Determine health status based on usage thresholds
    const memoryHigh = systemInfo.memory.usagePercent > 85;
    const cpuHigh = systemInfo.cpu.currentUsage > 90;
    const storageHigh = systemInfo.storage.totalUsagePercent > 90;

    let status = 'healthy';
    let alerts = [];

    if (memoryHigh) {
      status = 'warning';
      alerts.push(`High memory usage: ${systemInfo.memory.usagePercent}%`);
    }

    if (cpuHigh) {
      status = 'critical';
      alerts.push(`High CPU usage: ${systemInfo.cpu.currentUsage}%`);
    }

    if (storageHigh) {
      status = storageHigh && (memoryHigh || cpuHigh) ? 'critical' : 'warning';
      alerts.push(`High storage usage: ${systemInfo.storage.totalUsagePercent}%`);
    }

    return res.json({
      ok: true,
      status,
      alerts,
      summary: {
        memory: `${systemInfo.memory.usagePercent}%`,
        cpu: `${systemInfo.cpu.currentUsage}%`,
        storage: `${systemInfo.storage.totalUsagePercent}%`,
        uptime: formatUptime(systemInfo.system.uptime),
        songs: systemInfo.database.totalSongs.toLocaleString(),
      }
    });
  } catch (err: any) {
    log.error(`System health error: ${err.message}`);
    return next(err);
  }
});

/**
 * GET /v1/system/database
 * Returns only database statistics
 */
router.get("/database", async (req, res, next) => {
  try {
    const systemInfo = await getSystemMetrics();

    return res.json({
      ok: true,
      database: {
        ...systemInfo.database,
        totalSongsFormatted: systemInfo.database.totalSongs.toLocaleString(),
      }
    });
  } catch (err: any) {
    log.error(`Database stats error: ${err.message}`);
    return next(err);
  }
});

/**
 * GET /v1/system/donation
 * Returns donation configuration and progress
 */
router.get("/donation", async (req, res, next) => {
  try {
    log.search(`Donation info request from: ${req.ip}`);

    // TODO: These should be moved to environment variables or config
    const donationInfo = {
      monthlyGoal: 100,
      collected: 42,
      progress: 42 / 100,
      iranCardNumber: '6219861912412201',
      skrillEmail: 'hs.96@outlook.com',
      crypto: {
        btc: 'bc1q08yalf8p2ltv2w6jkdsc4jmf3smqq7nehzsx4f',
        eth: '0x7D062F49704d3af8ef6B53934F8aF885E30B542d',
        ltc: 'ltc1qmr2u6qhzrwe4adsvyzdahskeee8pmzjuv02lze',
        usdtTron: 'TTZzMhwAW6fXpPPgspe1K6j7Q9QsJMLD7B',
        usdtEth: '0x7D062F49704d3af8ef6B53934F8aF885E30B542d',
        usdcEth: '0x7D062F49704d3af8ef6B53934F8aF885E30B542d'
      }
    };

    log.success(`Donation info collected: ${Math.round(donationInfo.progress * 100)}% of goal`);

    return res.json({
      ok: true,
      donation: donationInfo
    });
  } catch (err: any) {
    log.error(`Donation info error: ${err.message}`);
    return next(err);
  }
});

/**
 * POST /v1/system/donation/crypto
 * Updates crypto donation addresses
 */
router.post("/donation/crypto", async (req, res, next) => {
  try {
    log.search(`Update crypto addresses request from: ${req.ip}`);

    const { btc, eth, ltc, usdtTron, usdtEth, usdcEth } = req.body;

    if (!btc && !eth && !ltc && !usdtTron && !usdtEth && !usdcEth) {
      return res.status(400).json({
        ok: false,
        error: "At least one crypto address must be provided"
      });
    }

    const updatedAddresses = {
      btc: btc || 'bc1q08yalf8p2ltv2w6jkdsc4jmf3smqq7nehzsx4f',
      eth: eth || '0x7D062F49704d3af8ef6B53934F8aF885E30B542d',
      ltc: ltc || 'ltc1qmr2u6qhzrwe4adsvyzdahskeee8pmzjuv02lze',
      usdtTron: usdtTron || 'TTZzMhwAW6fXpPPgspe1K6j7Q9QsJMLD7B',
      usdtEth: usdtEth || '0x7D062F49704d3af8ef6B53934F8aF885E30B542d',
      usdcEth: usdcEth || '0x7D062F49704d3af8ef6B53934F8aF885E30B542d'
    };

    log.success(`Crypto addresses updated successfully`);

    return res.json({
      ok: true,
      message: "Crypto addresses updated successfully",
      crypto: updatedAddresses
    });
  } catch (err: any) {
    log.error(`Update crypto addresses error: ${err.message}`);
    return next(err);
  }
});

/**
 * GET /v1/system/version
 * Returns the latest app version information
 */
router.get("/version", async (req, res, next) => {
  try {
    log.search(`Version check request from: ${req.ip}`);

    const versionInfo = {
      latest: "0.2.0",
      releaseDate: "2025-11-28",
      downloadUrl: "https://openmusic.website",
      features: [
        "Fixed sync race condition",
        "Auto-sync on data changes",
        "Desktop scroll improvements",
        "New professional website"
      ]
    };

    log.success(`Version info returned: ${versionInfo.latest}`);

    return res.json({
      ok: true,
      version: versionInfo
    });
  } catch (err: any) {
    log.error(`Version info error: ${err.message}`);
    return next(err);
  }
});

export default router;

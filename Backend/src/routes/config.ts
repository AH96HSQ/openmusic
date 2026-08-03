import { Router } from "express";
import { log } from "../utils/logger";

const router = Router();

/**
 * GET /v1/config/spotify-credentials
 * Returns Spotify API credentials for on-device search
 * The app has default credentials, but this endpoint allows updating them
 * without requiring an app update
 */
router.get("/spotify-credentials", async (_req, res, next) => {
  try {
    // Check if custom credentials are configured
    const clientId = process.env.SPOTIFY_CLIENT_ID_PUBLIC;
    const clientSecret = process.env.SPOTIFY_CLIENT_SECRET_PUBLIC;

    // If public credentials are not set, return 404 (app will use defaults)
    if (!clientId || !clientSecret) {
      log.info("Config: No public Spotify credentials configured, app will use defaults");
      res.status(404).json({ 
        error: "No custom credentials configured",
        useDefaults: true 
      });
      return;
    }

    log.info("Config: Returning public Spotify credentials");
    res.json({
      clientId,
      clientSecret,
      // Optional: include expiration/version info for caching
      version: process.env.SPOTIFY_CREDS_VERSION || "1",
    });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /v1/config/app-settings
 * Returns general app configuration settings
 * Can be extended for other runtime configs
 */
router.get("/app-settings", async (_req, res, next) => {
  try {
    res.json({
      // Feature flags
      features: {
        onDeviceSearch: true,  // Enable on-device Spotify search
        onDeviceDownload: true, // Enable on-device downloading
      },
      // Market configuration
      defaultMarket: process.env.SPOTIFY_MARKET || "US",
      // Version info
      configVersion: "1",
    });
  } catch (err) {
    next(err);
  }
});

/**
 * GET /v1/config/download-credentials
 * Returns API keys for on-device downloading
 * The app has default credentials, but this endpoint allows updating them
 * without requiring an app update
 */
router.get("/download-credentials", async (_req, res, next) => {
  try {
    // Check if custom credentials are configured
    const rapidApiKey = process.env.RAPIDAPI_KEY_PUBLIC;
    const dsRapidApiKey = process.env.DS_RAPIDAPI_KEY_PUBLIC;

    // If no custom credentials are set, return 404 (app will use defaults)
    if (!rapidApiKey && !dsRapidApiKey) {
      log.info("Config: No public download credentials configured, app will use defaults");
      res.status(404).json({ 
        error: "No custom download credentials configured",
        useDefaults: true 
      });
      return;
    }

    log.info("Config: Returning public download credentials");
    res.json({
      rapidApiKey: rapidApiKey || undefined,
      dsRapidApiKey: dsRapidApiKey || undefined,
      version: process.env.DOWNLOAD_CREDS_VERSION || "1",
    });
  } catch (err) {
    next(err);
  }
});

export default router;

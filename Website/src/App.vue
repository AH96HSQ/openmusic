<template>
  <div id="app">
    <!-- Navigation -->
    <nav class="navbar" aria-label="Main navigation">
      <div class="nav-content">
        <div class="nav-brand">
          <img src="./assets/Logo.png" alt="OpenMusic" class="nav-logo" />
          <span class="nav-title">OpenMusic</span>
        </div>
        <div class="nav-links">
          <a href="#features">Features</a>
          <a href="#platforms">Platforms</a>
          <a href="#download">Download</a>
          <a href="#faq">FAQ</a>
          <a href="https://github.com/AH96HSQ/OpenMusic-Release" target="_blank" class="github-link" rel="noopener noreferrer">
            <svg height="20" width="20" viewBox="0 0 16 16" fill="currentColor">
              <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/>
            </svg>
            GitHub
          </a>
        </div>
      </div>
    </nav>

    <!-- Hero Section -->
    <header class="hero" role="banner">
      <div class="hero-background" aria-hidden="true">
        <div class="gradient-orb orb-1"></div>
        <div class="gradient-orb orb-2"></div>
        <div class="gradient-orb orb-3"></div>
      </div>
      <div class="hero-content">
        <div class="hero-text">
          <div class="badge">🎵 Completely Free</div>
          <h1>Stream Music <span class="highlight-text">Your Way</span></h1>
          <p class="hero-subtitle">
            Experience music streaming without limits. OpenMusic brings you high-quality audio, 
            offline playback, and seamless syncing across all your devices.
          </p>
          <div class="hero-buttons">
            <a href="#download" class="btn btn-primary">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
                <polyline points="7,10 12,15 17,10"/>
                <line x1="12" y1="15" x2="12" y2="3"/>
              </svg>
              Download Now
            </a>
            <a href="https://github.com/AH96HSQ/OpenMusic-Release" target="_blank" class="btn btn-secondary">
              Learn More
            </a>
          </div>
        </div>
        <div class="hero-devices">
          <!-- Laptop Mockup -->
          <div class="laptop-mockup">
            <div class="laptop-screen">
              <img src="./assets/screenshot-windows.png" alt="OpenMusic on Windows" />
            </div>
            <div class="laptop-base"></div>
          </div>
          <!-- Phone Mockup -->
          <div class="phone-mockup">
            <div class="phone-screen">
              <img src="./assets/screenshot-android.jpg" alt="OpenMusic on Android" />
            </div>
          </div>
        </div>
      </div>
    </header>

    <!-- Main Content -->
    <main>
    <!-- Features Section -->
    <section id="features" class="features" aria-labelledby="features-title">
      <div class="section-content">
        <h2 id="features-title" class="section-title">Why Choose OpenMusic?</h2>
        <p class="section-subtitle">Built for music lovers who want freedom and quality</p>
        <div class="features-grid">
          <div class="feature-card">
            <div class="feature-icon">🎧</div>
            <h3>High Quality Audio</h3>
            <p>Stream and download music in the highest quality available for the best listening experience.</p>
          </div>
          <div class="feature-card">
            <div class="feature-icon">📱</div>
            <h3>Cross-Platform</h3>
            <p>Available on Windows and Android. Take your music library with you everywhere.</p>
          </div>
          <div class="feature-card">
            <div class="feature-icon">☁️</div>
            <h3>Cloud Sync</h3>
            <p>Your library, playlists, and preferences sync seamlessly across all your devices.</p>
          </div>
          <div class="feature-card">
            <div class="feature-icon">📥</div>
            <h3>Offline Mode</h3>
            <p>Download songs for offline listening. No internet? No problem.</p>
          </div>
          <div class="feature-card">
            <div class="feature-icon">🎨</div>
            <h3>Beautiful UI</h3>
            <p>Modern, clean interface with customizable themes to match your style.</p>
          </div>
          <div class="feature-card">
            <div class="feature-icon">💯</div>
            <h3>Completely Free</h3>
            <p>No subscriptions, no ads, no hidden costs. Just pure music enjoyment.</p>
          </div>
        </div>
      </div>
    </section>

    <!-- Platforms Section -->
    <section id="platforms" class="platforms" aria-labelledby="platforms-title">
      <div class="section-content">
        <h2 id="platforms-title" class="section-title">Available Platforms</h2>
        <p class="section-subtitle">One app, multiple platforms, seamless experience</p>
        <div class="platforms-showcase">
          <div class="platform-card windows">
            <div class="platform-icon">
              <svg width="48" height="48" viewBox="0 0 24 24" fill="currentColor">
                <path d="M0 3.449L9.75 2.1v9.451H0m10.949-9.602L24 0v11.4H10.949M0 12.6h9.75v9.451L0 20.699M10.949 12.6H24V24l-12.9-1.801"/>
              </svg>
            </div>
            <h3>Windows</h3>
            <p>Full desktop experience with all features</p>
            <span class="platform-status available">Available Now</span>
          </div>
          <div class="platform-card android">
            <div class="platform-icon">
              <svg width="48" height="48" viewBox="0 0 24 24" fill="currentColor">
                <path d="M6 18c0 .55.45 1 1 1h1v3.5c0 .83.67 1.5 1.5 1.5s1.5-.67 1.5-1.5V19h2v3.5c0 .83.67 1.5 1.5 1.5s1.5-.67 1.5-1.5V19h1c.55 0 1-.45 1-1V8H6v10zM3.5 8C2.67 8 2 8.67 2 9.5v7c0 .83.67 1.5 1.5 1.5S5 17.33 5 16.5v-7C5 8.67 4.33 8 3.5 8zm17 0c-.83 0-1.5.67-1.5 1.5v7c0 .83.67 1.5 1.5 1.5s1.5-.67 1.5-1.5v-7c0-.83-.67-1.5-1.5-1.5zm-4.97-5.84l1.3-1.3c.2-.2.2-.51 0-.71-.2-.2-.51-.2-.71 0l-1.48 1.48C13.85 1.23 12.95 1 12 1c-.96 0-1.86.23-2.66.63L7.85.15c-.2-.2-.51-.2-.71 0-.2.2-.2.51 0 .71l1.31 1.31C6.97 3.26 6 5.01 6 7h12c0-1.99-.97-3.75-2.47-4.84zM10 5H9V4h1v1zm5 0h-1V4h1v1z"/>
              </svg>
            </div>
            <h3>Android</h3>
            <p>Full mobile experience on the go</p>
            <span class="platform-status available">Available Now</span>
          </div>
          <div class="platform-card ios">
            <div class="platform-icon">
              <svg width="48" height="48" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
              </svg>
            </div>
            <h3>iOS</h3>
            <p>iPhone and iPad support</p>
            <span class="platform-status coming-soon">Coming Soon</span>
          </div>
          <div class="platform-card macos">
            <div class="platform-icon">
              <svg width="48" height="48" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"/>
              </svg>
            </div>
            <h3>macOS</h3>
            <p>Native Mac experience</p>
            <span class="platform-status coming-soon">Coming Soon</span>
          </div>
        </div>
      </div>
    </section>

    <!-- Download Section -->
    <section id="download" class="download" aria-labelledby="download-title">
      <div class="section-content">
        <h2 id="download-title" class="section-title">Download OpenMusic</h2>
        <p class="section-subtitle">Get started in seconds</p>
        <div class="download-cards">
          <div class="download-card">
            <div class="download-icon windows-icon">
              <svg width="64" height="64" viewBox="0 0 24 24" fill="currentColor">
                <path d="M0 3.449L9.75 2.1v9.451H0m10.949-9.602L24 0v11.4H10.949M0 12.6h9.75v9.451L0 20.699M10.949 12.6H24V24l-12.9-1.801"/>
              </svg>
            </div>
            <h3>Windows</h3>
            <p class="version">Version 0.2.0</p>
            <a href="https://github.com/AH96HSQ/OpenMusic-Release/releases/download/v0.2/OpenMusic_Setup_0.2.0.exe" class="btn btn-download">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
                <polyline points="7,10 12,15 17,10"/>
                <line x1="12" y1="15" x2="12" y2="3"/>
              </svg>
              Download for Windows
            </a>
            <span class="file-info">Windows 10/11 • 64-bit • ~50MB</span>
          </div>
          <div class="download-card">
            <div class="download-icon android-icon">
              <svg width="64" height="64" viewBox="0 0 24 24" fill="currentColor">
                <path d="M6 18c0 .55.45 1 1 1h1v3.5c0 .83.67 1.5 1.5 1.5s1.5-.67 1.5-1.5V19h2v3.5c0 .83.67 1.5 1.5 1.5s1.5-.67 1.5-1.5V19h1c.55 0 1-.45 1-1V8H6v10zM3.5 8C2.67 8 2 8.67 2 9.5v7c0 .83.67 1.5 1.5 1.5S5 17.33 5 16.5v-7C5 8.67 4.33 8 3.5 8zm17 0c-.83 0-1.5.67-1.5 1.5v7c0 .83.67 1.5 1.5 1.5s1.5-.67 1.5-1.5v-7c0-.83-.67-1.5-1.5-1.5zm-4.97-5.84l1.3-1.3c.2-.2.2-.51 0-.71-.2-.2-.51-.2-.71 0l-1.48 1.48C13.85 1.23 12.95 1 12 1c-.96 0-1.86.23-2.66.63L7.85.15c-.2-.2-.51-.2-.71 0-.2.2-.2.51 0 .71l1.31 1.31C6.97 3.26 6 5.01 6 7h12c0-1.99-.97-3.75-2.47-4.84zM10 5H9V4h1v1zm5 0h-1V4h1v1z"/>
              </svg>
            </div>
            <h3>Android</h3>
            <p class="version">Version 0.2.0</p>
            <a href="https://github.com/AH96HSQ/OpenMusic-Release/releases/download/v0.2/app-release.apk" class="btn btn-download">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
                <polyline points="7,10 12,15 17,10"/>
                <line x1="12" y1="15" x2="12" y2="3"/>
              </svg>
              Download APK
            </a>
            <span class="file-info">Android 7.0+ • ARM64 • ~55MB</span>
          </div>
        </div>
      </div>
    </section>

    <!-- FAQ Section -->
    <section id="faq" class="faq" aria-labelledby="faq-title">
      <div class="section-content">
        <h2 id="faq-title" class="section-title">Frequently Asked Questions</h2>
        <p class="section-subtitle">Got questions? We've got answers</p>
        <div class="faq-grid">
          <details class="faq-item">
            <summary>Is OpenMusic really free?</summary>
            <p>Yes, OpenMusic is completely free! No subscriptions, no ads, and no hidden costs. Just download and enjoy unlimited music streaming.</p>
          </details>
          <details class="faq-item">
            <summary>What platforms does OpenMusic support?</summary>
            <p>OpenMusic is currently available for Windows 10/11 and Android 7.0+. We're actively working on iOS and macOS versions, coming soon!</p>
          </details>
          <details class="faq-item">
            <summary>Can I listen to music offline?</summary>
            <p>Absolutely! OpenMusic supports offline mode. Download your favorite songs and listen anytime, anywhere - no internet required.</p>
          </details>
          <details class="faq-item">
            <summary>Does my music sync across devices?</summary>
            <p>Yes! With cloud sync, your library, playlists, and preferences sync seamlessly across all your devices. Start on your phone, continue on your PC.</p>
          </details>
          <details class="faq-item">
            <summary>What audio quality does OpenMusic support?</summary>
            <p>OpenMusic streams and downloads music in the highest quality available, ensuring the best listening experience for audiophiles and casual listeners alike.</p>
          </details>
          <details class="faq-item">
            <summary>How do I install OpenMusic on Android?</summary>
            <p>Download the APK file from our website, enable "Install from unknown sources" in your Android settings, and run the APK to install. It's that simple!</p>
          </details>
        </div>
      </div>
    </section>
    </main>

    <!-- Footer -->
    <footer class="footer">
      <div class="footer-content">
        <div class="footer-brand">
          <img src="./assets/Logo.png" alt="OpenMusic" class="footer-logo" />
          <span>OpenMusic</span>
        </div>
        <div class="footer-links">
          <a href="https://github.com/AH96HSQ/OpenMusic-Release" target="_blank">GitHub</a>
          <a href="https://github.com/AH96HSQ/OpenMusic-Release/issues" target="_blank">Report Issues</a>
          <a href="https://github.com/AH96HSQ/OpenMusic-Release/releases" target="_blank">All Releases</a>
        </div>
        <p class="copyright">© 2025 OpenMusic. Completely Free.</p>
      </div>
    </footer>
  </div>
</template>

<script>
export default {
  name: 'App',
}
</script>

<style>
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

:root {
  --primary: #006a6a;
  --primary-light: #00a3a3;
  --primary-dark: #004d4d;
  --bg-dark: #0a0a0a;
  --bg-card: #141414;
  --bg-card-hover: #1a1a1a;
  --text-primary: #ffffff;
  --text-secondary: #a0a0a0;
  --text-muted: #666666;
  --border: #2a2a2a;
  --gradient-start: #006a6a;
  --gradient-end: #00a3a3;
}

body, html {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', sans-serif;
  background: var(--bg-dark);
  color: var(--text-primary);
  scroll-behavior: smooth;
  overflow-x: hidden;
}

/* Navigation */
.navbar {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  z-index: 1000;
  background: rgba(10, 10, 10, 0.8);
  backdrop-filter: blur(20px);
  border-bottom: 1px solid var(--border);
}

.nav-content {
  max-width: 1200px;
  margin: 0 auto;
  padding: 16px 24px;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.nav-brand {
  display: flex;
  align-items: center;
  gap: 12px;
}

.nav-logo {
  width: 36px;
  height: 36px;
}

.nav-title {
  font-size: 1.25rem;
  font-weight: 700;
  color: #ffffff;
}

.nav-links {
  display: flex;
  align-items: center;
  gap: 32px;
}

.nav-links a {
  color: var(--text-secondary);
  text-decoration: none;
  font-size: 0.9rem;
  transition: color 0.2s;
}

.nav-links a:hover {
  color: var(--text-primary);
}

.github-link {
  display: flex;
  align-items: center;
  gap: 8px;
}

/* Hero Section */
.hero {
  min-height: 100vh;
  padding: 120px 24px 80px;
  position: relative;
  overflow: hidden;
}

.hero-background {
  position: absolute;
  inset: 0;
  overflow: hidden;
}

.gradient-orb {
  position: absolute;
  border-radius: 50%;
  filter: blur(80px);
  opacity: 0.4;
}

.orb-1 {
  width: 600px;
  height: 600px;
  background: var(--primary);
  top: -200px;
  right: -200px;
  animation: float 20s infinite ease-in-out;
}

.orb-2 {
  width: 400px;
  height: 400px;
  background: var(--primary-light);
  bottom: -100px;
  left: -100px;
  animation: float 15s infinite ease-in-out reverse;
}

.orb-3 {
  width: 300px;
  height: 300px;
  background: var(--primary-dark);
  top: 50%;
  left: 50%;
  animation: float 25s infinite ease-in-out;
}

@keyframes float {
  0%, 100% { transform: translate(0, 0); }
  25% { transform: translate(30px, -30px); }
  50% { transform: translate(-20px, 20px); }
  75% { transform: translate(20px, 10px); }
}

.hero-content {
  max-width: 1200px;
  margin: 0 auto;
  display: grid;
  grid-template-columns: 1fr 1.2fr;
  gap: 60px;
  align-items: center;
  position: relative;
  z-index: 1;
}

.hero-text {
  max-width: 560px;
}

.badge {
  display: inline-block;
  padding: 8px 16px;
  background: rgba(255, 255, 255, 0.15);
  border: 1px solid rgba(255, 255, 255, 0.3);
  border-radius: 100px;
  font-size: 0.85rem;
  color: #ffffff;
  margin-bottom: 24px;
  backdrop-filter: blur(10px);
}

.hero h1 {
  font-size: 3.5rem;
  font-weight: 800;
  line-height: 1.1;
  margin-bottom: 24px;
  color: #ffffff;
  text-shadow: 0 2px 20px rgba(0, 0, 0, 0.3);
}

.gradient-text {
  background: linear-gradient(135deg, var(--gradient-start), var(--gradient-end));
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

.highlight-text {
  color: #ffffff;
  text-shadow: 0 0 40px rgba(255, 255, 255, 0.3);
}

.hero-subtitle {
  font-size: 1.2rem;
  color: rgba(255, 255, 255, 0.85);
  line-height: 1.7;
  margin-bottom: 36px;
  text-shadow: 0 1px 10px rgba(0, 0, 0, 0.2);
}

.hero-buttons {
  display: flex;
  gap: 16px;
}

.btn {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  padding: 14px 28px;
  border-radius: 12px;
  font-size: 1rem;
  font-weight: 600;
  text-decoration: none;
  transition: all 0.3s;
  cursor: pointer;
  border: none;
}

.btn-primary {
  background: #ffffff;
  color: #006a6a;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.2);
}

.btn-primary:hover {
  transform: translateY(-2px);
  box-shadow: 0 6px 30px rgba(0, 0, 0, 0.3);
  background: #f0f0f0;
}

.btn-secondary {
  background: rgba(255, 255, 255, 0.1);
  color: #ffffff;
  border: 1px solid rgba(255, 255, 255, 0.3);
  backdrop-filter: blur(10px);
}

.btn-secondary:hover {
  background: rgba(255, 255, 255, 0.2);
  border-color: rgba(255, 255, 255, 0.5);
}

/* Device Mockups */
.hero-devices {
  position: relative;
  height: 500px;
}

.laptop-mockup {
  position: absolute;
  left: 0;
  top: 20px;
  width: 580px;
}

.laptop-screen {
  background: #1a1a1a;
  border-radius: 12px 12px 0 0;
  padding: 8px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
}

.laptop-screen img {
  width: 100%;
  border-radius: 6px;
  display: block;
}

.laptop-base {
  height: 16px;
  background: linear-gradient(to bottom, #3a3a3a, #2a2a2a);
  border-radius: 0 0 8px 8px;
  position: relative;
}

.laptop-base::after {
  content: '';
  position: absolute;
  top: 4px;
  left: 50%;
  transform: translateX(-50%);
  width: 80px;
  height: 6px;
  background: #1a1a1a;
  border-radius: 4px;
}

.phone-mockup {
  position: absolute;
  right: 40px;
  bottom: 0;
  width: 200px;
  background: #1a1a1a;
  border-radius: 32px;
  padding: 12px;
  box-shadow: 0 30px 80px rgba(0, 0, 0, 0.6);
  border: 2px solid #2a2a2a;
}

.phone-screen {
  border-radius: 20px;
  overflow: hidden;
}

.phone-screen img {
  width: 100%;
  display: block;
}

/* Sections */
.section-content {
  max-width: 1200px;
  margin: 0 auto;
  padding: 0 24px;
}

.section-title {
  font-size: 2.5rem;
  font-weight: 800;
  text-align: center;
  margin-bottom: 16px;
  color: #ffffff;
}

.section-subtitle {
  text-align: center;
  color: var(--text-secondary);
  font-size: 1.1rem;
  margin-bottom: 60px;
}

/* Features */
.features {
  padding: 120px 24px;
  background: var(--bg-dark);
}

.features-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 24px;
}

.feature-card {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 20px;
  padding: 32px;
  transition: all 0.3s;
}

.feature-card:hover {
  background: var(--bg-card-hover);
  border-color: var(--primary);
  transform: translateY(-4px);
}

.feature-icon {
  font-size: 2.5rem;
  margin-bottom: 20px;
}

.feature-card h3 {
  font-size: 1.25rem;
  margin-bottom: 12px;
  color: #ffffff;
}

.feature-card p {
  color: var(--text-secondary);
  line-height: 1.6;
}

/* Platforms */
.platforms {
  padding: 120px 24px;
  background: linear-gradient(180deg, var(--bg-dark) 0%, #0f1a1a 100%);
}

.platforms-showcase {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 24px;
}

.platform-card {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 20px;
  padding: 40px 24px;
  text-align: center;
  transition: all 0.3s;
}

.platform-card:hover {
  transform: translateY(-4px);
  border-color: var(--primary);
}

.platform-icon {
  color: var(--primary-light);
  margin-bottom: 20px;
}

.platform-card h3 {
  font-size: 1.25rem;
  margin-bottom: 8px;
  color: #ffffff;
}

.platform-card p {
  color: var(--text-secondary);
  font-size: 0.9rem;
  margin-bottom: 16px;
}

.platform-status {
  display: inline-block;
  padding: 6px 16px;
  border-radius: 100px;
  font-size: 0.8rem;
  font-weight: 600;
}

.platform-status.available {
  background: rgba(0, 200, 100, 0.15);
  color: #00c864;
}

.platform-status.coming-soon {
  background: rgba(255, 200, 0, 0.15);
  color: #ffc800;
}

/* Download */
.download {
  padding: 120px 24px;
  background: var(--bg-dark);
}

.download-cards {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 32px;
  max-width: 800px;
  margin: 0 auto;
}

.download-card {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 24px;
  padding: 48px 32px;
  text-align: center;
  transition: all 0.3s;
}

.download-card:hover {
  border-color: var(--primary);
  transform: translateY(-4px);
}

.download-icon {
  margin-bottom: 24px;
}

.windows-icon { color: #0078d4; }
.android-icon { color: #3ddc84; }

.download-card h3 {
  font-size: 1.5rem;
  margin-bottom: 8px;
  color: #ffffff;
}

.version {
  color: var(--text-secondary);
  margin-bottom: 24px;
}

.btn-download {
  background: linear-gradient(135deg, var(--gradient-start), var(--gradient-end));
  color: white;
  width: 100%;
  justify-content: center;
  margin-bottom: 16px;
  box-shadow: 0 4px 20px rgba(0, 106, 106, 0.3);
}

.btn-download:hover {
  transform: translateY(-2px);
  box-shadow: 0 6px 30px rgba(0, 106, 106, 0.4);
}

.file-info {
  font-size: 0.8rem;
  color: var(--text-muted);
}

/* Footer */
.footer {
  background: var(--bg-card);
  border-top: 1px solid var(--border);
  padding: 48px 24px;
}

.footer-content {
  max-width: 1200px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 24px;
}

.footer-brand {
  display: flex;
  align-items: center;
  gap: 12px;
  font-size: 1.25rem;
  font-weight: 700;
}

.footer-logo {
  width: 32px;
  height: 32px;
}

.footer-links {
  display: flex;
  gap: 32px;
}

.footer-links a {
  color: var(--text-secondary);
  text-decoration: none;
  transition: color 0.2s;
}

.footer-links a:hover {
  color: var(--primary-light);
}

.copyright {
  color: var(--text-muted);
  font-size: 0.9rem;
}

/* FAQ Section */
.faq {
  padding: 120px 24px;
  background: linear-gradient(180deg, var(--bg-dark) 0%, #0f1a1a 100%);
}

.faq-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 16px;
  max-width: 1000px;
  margin: 0 auto;
}

.faq-item {
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 16px;
  overflow: hidden;
  transition: all 0.3s;
}

.faq-item:hover {
  border-color: var(--primary);
}

.faq-item summary {
  padding: 20px 24px;
  font-size: 1rem;
  font-weight: 600;
  cursor: pointer;
  list-style: none;
  color: #ffffff;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.faq-item summary::-webkit-details-marker {
  display: none;
}

.faq-item summary::after {
  content: '+';
  font-size: 1.5rem;
  color: var(--primary-light);
  transition: transform 0.3s;
}

.faq-item[open] summary::after {
  content: '−';
}

.faq-item p {
  padding: 0 24px 20px;
  color: var(--text-secondary);
  line-height: 1.7;
}

/* Responsive */
@media (max-width: 1024px) {
  .hero-content {
    grid-template-columns: 1fr;
    text-align: center;
  }

  .hero-text {
    max-width: 100%;
  }

  .hero-buttons {
    justify-content: center;
  }

  .hero-devices {
    height: 400px;
  }

  .laptop-mockup {
    width: 100%;
    max-width: 500px;
    left: 50%;
    transform: translateX(-50%);
  }

  .phone-mockup {
    width: 140px;
    right: 10%;
    bottom: -40px;
  }

  .features-grid {
    grid-template-columns: repeat(2, 1fr);
  }

  .platforms-showcase {
    grid-template-columns: repeat(2, 1fr);
  }
}

@media (max-width: 768px) {
  .nav-links {
    display: none;
  }

  .hero h1 {
    font-size: 2.5rem;
  }

  .hero-devices {
    height: 350px;
  }

  .laptop-mockup {
    max-width: 400px;
  }

  .phone-mockup {
    width: 120px;
  }

  .features-grid {
    grid-template-columns: 1fr;
  }

  .platforms-showcase {
    grid-template-columns: 1fr 1fr;
  }

  .download-cards {
    grid-template-columns: 1fr;
  }

  .section-title {
    font-size: 2rem;
  }

  .faq-grid {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 480px) {
  .hero h1 {
    font-size: 2rem;
  }

  .hero-buttons {
    flex-direction: column;
  }

  .btn {
    width: 100%;
    justify-content: center;
  }

  .hero-devices {
    height: 300px;
  }

  .laptop-mockup {
    max-width: 300px;
  }

  .phone-mockup {
    width: 100px;
  }

  .platforms-showcase {
    grid-template-columns: 1fr;
  }
}
</style>

import express from 'express';
import { User } from '../models/User';

const router = express.Router();

// Store OTPs temporarily (in production, use Redis with TTL)
const otpStore = new Map<string, { otp: string; timestamp: number }>();

// Clean up expired OTPs (older than 10 minutes)
setInterval(() => {
  const now = Date.now();
  for (const [email, data] of otpStore.entries()) {
    if (now - data.timestamp > 600000) { // 10 minutes
      otpStore.delete(email);
    }
  }
}, 60000); // Clean every minute

// POST /api/auth/check-email
router.post('/check-email', async (req, res) => {
  const { email } = req.body;

  if (!email) {
    res.status(400).json({ success: false, error: 'Email is required' });
    return;
  }

  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(email)) {
    res.status(400).json({ success: false, error: 'Invalid email format' });
    return;
  }

  try {
    const user = await User.findOne({ email: email.toLowerCase() });
    
    res.json({
      success: true,
      exists: !!user,
      requiresPassword: !!user,
      requiresOtp: !user,
    });
  } catch (err: any) {
    console.error('❌ Check email failed:', err);
    res.status(500).json({ success: false, error: 'Server error' });
  }
});

// POST /api/auth/login
router.post('/login', async (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    res.status(400).json({ success: false, error: 'Email and password are required' });
    return;
  }

  try {
    const user = await User.findOne({ email: email.toLowerCase() });
    
    if (!user) {
      res.status(401).json({ success: false, error: 'Invalid email or password' });
      return;
    }

    // Simple password comparison (in production, use bcrypt)
    if (user.password !== password) {
      res.status(401).json({ success: false, error: 'Invalid email or password' });
      return;
    }

    console.log('✅ User logged in:', email);
    res.json({
      success: true,
      user: {
        id: user._id,
        email: user.email,
        createdAt: user.createdAt,
      },
    });
  } catch (err: any) {
    console.error('❌ Login failed:', err);
    res.status(500).json({ success: false, error: 'Server error' });
  }
});

// POST /api/auth/verify-otp
router.post('/verify-otp', async (req, res) => {
  const { email, otp } = req.body;

  if (!email || !otp) {
    res.status(400).json({ success: false, error: 'Email and OTP are required' });
    return;
  }

  try {
    const storedOtp = otpStore.get(email.toLowerCase());
    
    if (!storedOtp) {
      res.status(400).json({ success: false, error: 'OTP expired or not found' });
      return;
    }

    // Check if OTP is expired (10 minutes)
    if (Date.now() - storedOtp.timestamp > 600000) {
      otpStore.delete(email.toLowerCase());
      res.status(400).json({ success: false, error: 'OTP expired' });
      return;
    }

    if (storedOtp.otp !== otp) {
      res.status(400).json({ success: false, error: 'Invalid OTP' });
      return;
    }

    // OTP is valid, remove it from store
    otpStore.delete(email.toLowerCase());
    
    console.log('✅ OTP verified for:', email);
    res.json({ success: true, verified: true });
  } catch (err: any) {
    console.error('❌ OTP verification failed:', err);
    res.status(500).json({ success: false, error: 'Server error' });
  }
});

// POST /api/auth/create-account
router.post('/create-account', async (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    res.status(400).json({ success: false, error: 'Email and password are required' });
    return;
  }

  if (password.length < 6) {
    res.status(400).json({ success: false, error: 'Password must be at least 6 characters' });
    return;
  }

  try {
    // Check if user already exists
    const existingUser = await User.findOne({ email: email.toLowerCase() });
    if (existingUser) {
      res.status(400).json({ success: false, error: 'Email already registered' });
      return;
    }

    // Create new user (in production, hash password with bcrypt)
    const user = new User({
      email: email.toLowerCase(),
      password: password, // TODO: Hash this in production!
    });

    await user.save();

    console.log('✅ Account created for:', email);
    res.json({
      success: true,
      user: {
        id: user._id,
        email: user.email,
        createdAt: user.createdAt,
      },
    });
  } catch (err: any) {
    console.error('❌ Account creation failed:', err);
    res.status(500).json({ success: false, error: 'Server error' });
  }
});

// POST /api/auth/reset-password
router.post('/reset-password', async (req, res) => {
  const { email, newPassword } = req.body;

  if (!email || !newPassword) {
    res.status(400).json({ success: false, error: 'Email and new password are required' });
    return;
  }

  if (newPassword.length < 6) {
    res.status(400).json({ success: false, error: 'Password must be at least 6 characters' });
    return;
  }

  try {
    // Find user
    const user = await User.findOne({ email: email.toLowerCase() });
    if (!user) {
      res.status(404).json({ success: false, error: 'User not found' });
      return;
    }

    // Update password (in production, hash with bcrypt)
    user.password = newPassword; // TODO: Hash this in production!
    await user.save();

    console.log('✅ Password reset for:', email);
    res.json({
      success: true,
      message: 'Password reset successfully',
    });
  } catch (err: any) {
    console.error('❌ Password reset failed:', err);
    res.status(500).json({ success: false, error: 'Server error' });
  }
});

// Function to store OTP (called from email route)
export function storeOTP(email: string, otp: string) {
  otpStore.set(email.toLowerCase(), { otp, timestamp: Date.now() });
}

export default router;

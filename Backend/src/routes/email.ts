import express from 'express';
import nodemailer from 'nodemailer';
import { storeOTP } from './auth';

const router = express.Router();

// Helper function to generate 6-digit OTP
function generateOTP(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// POST /api/email/request-otp
router.post('/request-otp', async (req, res) => {
  const { email } = req.body;

  // Validate email
  if (!email) {
    res.status(400).json({ 
      success: false, 
      error: 'Email is required' 
    });
    return;
  }

  // Basic email validation
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(email)) {
    res.status(400).json({ 
      success: false, 
      error: 'Invalid email format' 
    });
    return;
  }

  // Generate OTP
  const otp = generateOTP();

  const transporter = nodemailer.createTransport({
    host: 'mail8.limoo.host',
    port: 465,
    secure: true,
    auth: {
      user: 'support@zurtex.net',
      pass: process.env.SMTP_PASS,
    },
  });

  try {
    const info = await transporter.sendMail({
      from: '"OpenMusic" <support@zurtex.net>',
      to: email,
      subject: 'Your OpenMusic Verification Code',
      text: `Your verification code is: ${otp}\n\nThis code will expire in 10 minutes.\n\nIf you didn't request this code, please ignore this email.`,
      html: `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
          <h2 style="color: #333;">OpenMusic Verification Code</h2>
          <p>Your verification code is:</p>
          <div style="background-color: #f0f0f0; padding: 20px; text-align: center; font-size: 32px; font-weight: bold; letter-spacing: 5px; margin: 20px 0;">
            ${otp}
          </div>
          <p style="color: #666;">This code will expire in 10 minutes.</p>
          <p style="color: #666;">If you didn't request this code, please ignore this email.</p>
          <hr style="border: none; border-top: 1px solid #ddd; margin: 20px 0;">
          <p style="color: #999; font-size: 12px;">OpenMusic - Your Music, Your Way</p>
        </div>
      `,
    });

    console.log('✅ OTP sent successfully:', info.messageId, 'to:', email);
    
    // Store OTP server-side
    storeOTP(email, otp);
    
    // Return success (don't send OTP to client in production for security)
    res.json({ 
      success: true,
      message: 'Verification code sent to your email',
      expiresIn: 600 // 10 minutes in seconds
    });
  } catch (err: any) {
    console.error('❌ OTP email send failed:', err);
    res.status(500).json({ 
      success: false, 
      error: err.message || 'Failed to send verification email' 
    });
  }
});

// POST /api/email/send (kept for backward compatibility if needed)
router.post('/send', async (req, res) => {
  const { to, subject, text } = req.body;

  // Validate required fields
  if (!to || !subject || !text) {
    res.status(400).json({ 
      success: false, 
      error: 'Missing required fields: to, subject, text' 
    });
    return;
  }

  const transporter = nodemailer.createTransport({
    host: 'mail8.limoo.host',
    port: 465,
    secure: true,
    auth: {
      user: 'support@zurtex.net',
      pass: process.env.SMTP_PASS,
    },
  });

  try {
    const info = await transporter.sendMail({
      from: '"OpenMusic" <support@zurtex.net>',
      to,
      subject,
      text,
    });

    console.log('✅ Email sent successfully:', info.messageId);
    res.json({ success: true, messageId: info.messageId });
  } catch (err: any) {
    console.error('❌ Email send failed:', err);
    res.status(500).json({ 
      success: false, 
      error: err.message || 'Failed to send email' 
    });
  }
});

export default router;

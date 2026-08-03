# Email System Setup

## Overview
The OpenMusic backend includes an automated email sending system with OTP (One-Time Password) verification support using nodemailer and SMTP.

## Configuration

### Environment Variables
Add the following to your `.env` file:

```env
SMTP_PASS=56746671sbbB
```

### SMTP Settings
- **Host**: mail8.limoo.host
- **Port**: 465 (SSL/TLS)
- **Sender**: support@zurtex.net
- **Display Name**: OpenMusic

## API Endpoints

### Request OTP (Email Verification)
```
POST /v1/email/request-otp
```

**Request Body:**
```json
{
  "email": "user@example.com"
}
```

**Success Response:**
```json
{
  "success": true,
  "otp": "123456",
  "expiresIn": 600
}
```

**Error Response:**
```json
{
  "success": false,
  "error": "Error message"
}
```

**Features:**
- Generates a random 6-digit OTP code
- Sends beautifully formatted HTML email with the code
- Returns OTP to client for verification
- 10-minute expiry time (600 seconds)
- Email validation

### Send Generic Email
```
POST /v1/email/send
```

**Request Body:**
```json
{
  "to": "recipient@example.com",
  "subject": "Your Subject",
  "text": "Your email message here"
}
```

**Success Response:**
```json
{
  "success": true,
  "messageId": "<unique-message-id>"
}
```

## Testing

### Test OTP Request (PowerShell)
```powershell
$body = @{
    email = "your-email@example.com"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:5002/v1/email/request-otp" `
                  -Method Post `
                  -ContentType "application/json" `
                  -Body $body
```

### Test OTP Request (cURL)
```bash
curl -X POST http://localhost:5002/v1/email/request-otp \
  -H "Content-Type: application/json" \
  -d '{"email": "your-email@example.com"}'
```

## Use Cases

This email system supports:
- ✅ Email verification with OTP codes
- ✅ User account creation/registration
- ✅ Password reset flows
- ✅ Two-factor authentication (2FA)
- ✅ Login verification
- ✅ Generic email notifications

## Security Notes

⚠️ **Important**: 
- Never commit your `.env` file with real passwords
- The SMTP password is sensitive - keep it secure
- Consider rotating passwords periodically
- Use environment-specific passwords for dev/prod
- In production, store OTPs server-side with Redis/database for better security
- Current implementation returns OTP to client - consider storing server-side with expiry

## OTP Email Template

The OTP email includes:
- Clean, professional HTML design
- Large, easy-to-read code display
- 10-minute expiry notice
- Security warning for unsolicited codes
- Responsive design for mobile devices

## Next Steps for Production

1. **Store OTPs Server-Side**: Use Redis or database with TTL (Time To Live)
2. **Rate Limiting**: Prevent spam by limiting OTP requests per email/IP
3. **Attempt Tracking**: Lock accounts after too many failed verification attempts
4. **Audit Logging**: Log all OTP requests and verification attempts
5. **Email Templates**: Create reusable email template system

## Troubleshooting

### Common Issues

1. **"Failed to send verification email"**
   - Check if SMTP_PASS is set in .env
   - Verify the password is correct
   - Ensure the server (mail8.limoo.host) is accessible

2. **"Invalid email format"**
   - Email must follow standard format: user@domain.com
   - Check for typos or extra spaces

3. **"Connection timeout"**
   - Check your firewall settings
   - Verify port 465 is not blocked
   - Try using port 587 with TLS if needed

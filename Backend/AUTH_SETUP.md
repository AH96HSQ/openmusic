# Authentication System Documentation

## Overview

OpenMusic uses an email-based authentication system with OTP verification for new users and password login for existing users.

## Authentication Flow

### For New Users (Registration)
1. User enters email address
2. System checks if email exists in database
3. If email doesn't exist:
   - Backend generates 6-digit OTP
   - OTP is sent via email
   - OTP is stored server-side with timestamp
   - User enters received OTP code
   - System verifies OTP against stored value
   - User creates password (minimum 6 characters)
   - Account is created in database
   - User is logged in

### For Existing Users (Login)
1. User enters email address
2. System checks if email exists in database
3. If email exists:
   - User is prompted for password
   - System verifies password
   - User is logged in

## API Endpoints

### 1. Check Email
**POST** `/v1/auth/check-email`

Check if an email address exists in the database.

**Request:**
```json
{
  "email": "user@example.com"
}
```

**Response:**
```json
{
  "success": true,
  "exists": true,
  "requiresPassword": true,
  "requiresOtp": false
}
```

OR

```json
{
  "success": true,
  "exists": false,
  "requiresPassword": false,
  "requiresOtp": true
}
```

### 2. Request OTP
**POST** `/v1/email/request-otp`

Send a verification code to the user's email.

**Request:**
```json
{
  "email": "newuser@example.com"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Verification code sent to your email",
  "expiresIn": 600
}
```

**Email Template:**
- Subject: "Your OpenMusic Verification Code"
- Contains 6-digit OTP in styled HTML format
- Includes expiry notice (10 minutes)
- Security warning

### 3. Verify OTP
**POST** `/v1/auth/verify-otp`

Verify the OTP code entered by the user.

**Request:**
```json
{
  "email": "newuser@example.com",
  "otp": "123456"
}
```

**Response (Success):**
```json
{
  "success": true,
  "verified": true
}
```

**Response (Error):**
```json
{
  "success": false,
  "error": "Invalid or expired OTP"
}
```

### 4. Login
**POST** `/v1/auth/login`

Login with email and password for existing users.

**Request:**
```json
{
  "email": "user@example.com",
  "password": "mypassword123"
}
```

**Response (Success):**
```json
{
  "success": true,
  "user": {
    "id": "507f1f77bcf86cd799439011",
    "email": "user@example.com",
    "createdAt": "2024-01-15T10:30:00.000Z"
  }
}
```

**Response (Error):**
```json
{
  "success": false,
  "error": "Invalid email or password"
}
```

### 5. Create Account
**POST** `/v1/auth/create-account`

Create a new user account after OTP verification.

**Request:**
```json
{
  "email": "newuser@example.com",
  "password": "mypassword123"
}
```

**Response (Success):**
```json
{
  "success": true,
  "user": {
    "id": "507f1f77bcf86cd799439011",
    "email": "newuser@example.com",
    "createdAt": "2024-01-15T10:30:00.000Z"
  }
}
```

**Response (Error):**
```json
{
  "success": false,
  "error": "Password must be at least 6 characters"
}
```

## Database Schema

### User Model
```typescript
{
  email: String (unique, lowercase, trimmed, required)
  password: String (required) // TODO: Hash with bcrypt in production
  createdAt: Date (auto-generated)
  updatedAt: Date (auto-generated)
}
```

## OTP Storage

OTPs are currently stored in-memory using a Map:
```typescript
Map<email, {otp: string, timestamp: number}>
```

**Features:**
- Automatic cleanup every 60 seconds
- OTPs expire after 10 minutes
- Deleted immediately after successful verification

**⚠️ Production Note:** For production, use Redis or another persistent store with TTL support.

## Security Considerations

### Current Implementation (Development)
- ❌ Passwords stored in plain text
- ❌ OTPs stored in-memory (lost on server restart)
- ❌ No rate limiting on OTP requests
- ❌ No session management
- ✅ Email validation with regex
- ✅ Password minimum length (6 characters)
- ✅ OTP automatic expiry (10 minutes)

### Production Recommendations

1. **Password Security**
   ```typescript
   import bcrypt from 'bcrypt';
   
   // Hash password
   const hashedPassword = await bcrypt.hash(password, 10);
   
   // Verify password
   const isValid = await bcrypt.compare(password, user.password);
   ```

2. **OTP Storage**
   - Use Redis with TTL for OTP storage
   - Example: `SETEX otp:email@example.com 600 123456`

3. **Rate Limiting**
   ```typescript
   import rateLimit from 'express-rate-limit';
   
   const otpLimiter = rateLimit({
     windowMs: 15 * 60 * 1000, // 15 minutes
     max: 3, // 3 requests per window
     message: 'Too many OTP requests, please try again later'
   });
   
   router.post('/request-otp', otpLimiter, ...);
   ```

4. **Session Management**
   - Implement JWT tokens for authenticated sessions
   - Store refresh tokens securely
   - Add token expiry and refresh mechanism

5. **Additional Security**
   - HTTPS only in production
   - CORS configuration for specific domains
   - Input sanitization
   - SQL injection prevention (using Mongoose handles this)
   - XSS protection

## Testing

### Test OTP Email (PowerShell)
```powershell
$body = @{
    email = "test@example.com"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:5002/v1/email/request-otp" `
    -Method Post `
    -ContentType "application/json" `
    -Body $body
```

### Test Full Registration Flow
```powershell
# 1. Check email (should not exist)
$checkBody = @{ email = "newuser@test.com" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:5002/v1/auth/check-email" -Method Post -ContentType "application/json" -Body $checkBody

# 2. Request OTP
$otpBody = @{ email = "newuser@test.com" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:5002/v1/email/request-otp" -Method Post -ContentType "application/json" -Body $otpBody

# 3. Verify OTP (use code from email)
$verifyBody = @{ email = "newuser@test.com"; otp = "123456" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:5002/v1/auth/verify-otp" -Method Post -ContentType "application/json" -Body $verifyBody

# 4. Create account
$createBody = @{ email = "newuser@test.com"; password = "testpass123" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:5002/v1/auth/create-account" -Method Post -ContentType "application/json" -Body $createBody
```

### Test Login Flow
```powershell
# 1. Check email (should exist)
$checkBody = @{ email = "newuser@test.com" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:5002/v1/auth/check-email" -Method Post -ContentType "application/json" -Body $checkBody

# 2. Login
$loginBody = @{ email = "newuser@test.com"; password = "testpass123" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:5002/v1/auth/login" -Method Post -ContentType "application/json" -Body $loginBody
```

## Flutter Integration

The Flutter app uses `AuthService` class (`lib/src/services/auth_service.dart`) to interact with these endpoints.

**Multi-Step UI Flow:**
1. Email input screen
2. Branch based on email existence:
   - Existing: Password login screen
   - New: OTP verification screen → Password creation screen
3. Logged in state

**State Management:**
- `AuthStep` enum tracks current step
- Controllers: `_emailController`, `_otpController`, `_passwordController`
- Loading state prevents duplicate requests
- Error messages displayed inline

## Environment Variables

Required in `.env` file:

```env
# Database
MONGO_URI=mongodb://localhost:27017/openmusic

# Email
SMTP_PASS=your_smtp_password_here

# Server
PORT=5002
```

## Error Handling

All endpoints return consistent error format:
```json
{
  "success": false,
  "error": "Descriptive error message"
}
```

Common errors:
- `"Email is required"`
- `"Invalid email format"`
- `"Invalid or expired OTP"`
- `"Invalid email or password"`
- `"Password must be at least 6 characters"`
- `"Email already registered"`

## Maintenance

### Clearing OTP Store
OTPs are automatically cleaned every 60 seconds. No manual intervention needed.

### User Management
```typescript
// Find user by email
const user = await User.findOne({ email: 'user@example.com' });

// Delete user
await User.deleteOne({ email: 'user@example.com' });

// Count users
const count = await User.countDocuments();
```

## Next Steps

- [ ] Implement bcrypt password hashing
- [ ] Move OTP storage to Redis
- [ ] Add rate limiting
- [ ] Implement JWT session management
- [ ] Add password reset functionality
- [ ] Add email verification resend feature
- [ ] Add user profile management endpoints
- [ ] Implement OAuth (Google, Apple) login

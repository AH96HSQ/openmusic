# Authentication System Test Script
# This script tests the complete authentication flow

Write-Host "=== OpenMusic Authentication System Test ===" -ForegroundColor Cyan
Write-Host ""

$baseUrl = "http://localhost:5002/v1"
$testEmail = "test_$(Get-Random)@openmusic.test"

# Test 1: Check Email (Should not exist)
Write-Host "Test 1: Checking if email exists (should be false)..." -ForegroundColor Yellow
try {
    $checkBody = @{ email = $testEmail } | ConvertTo-Json
    $checkResult = Invoke-RestMethod -Uri "$baseUrl/auth/check-email" -Method Post -ContentType "application/json" -Body $checkBody
    Write-Host "Success: Email check complete" -ForegroundColor Green
    Write-Host "  Exists: $($checkResult.exists)" -ForegroundColor Gray
    Write-Host "  Requires OTP: $($checkResult.requiresOtp)" -ForegroundColor Gray
    Write-Host ""
} catch {
    Write-Host "Failed: Email check error: $_" -ForegroundColor Red
    exit 1
}

# Test 2: Request OTP
Write-Host "Test 2: Requesting OTP for new user..." -ForegroundColor Yellow
try {
    $otpBody = @{ email = $testEmail } | ConvertTo-Json
    $otpResult = Invoke-RestMethod -Uri "$baseUrl/email/request-otp" -Method Post -ContentType "application/json" -Body $otpBody
    Write-Host "Success: OTP request complete" -ForegroundColor Green
    Write-Host "  Message: $($otpResult.message)" -ForegroundColor Gray
    Write-Host "  Expires in: $($otpResult.expiresIn) seconds" -ForegroundColor Gray
    Write-Host ""
} catch {
    Write-Host "Failed: OTP request error: $_" -ForegroundColor Red
    exit 1
}

# For testing, we need the actual OTP from the server
# In production, user would get it from email
Write-Host "NOTE: In production, OTP would be sent via email" -ForegroundColor Magenta
Write-Host "NOTE: For testing purposes, check your email or server logs" -ForegroundColor Magenta
Write-Host ""

# Prompt for OTP
$otp = Read-Host "Enter the OTP sent to email (or press Enter to skip verification test)"

if ($otp) {
    # Test 3: Verify OTP
    Write-Host "Test 3: Verifying OTP..." -ForegroundColor Yellow
    try {
        $verifyBody = @{ email = $testEmail; otp = $otp } | ConvertTo-Json
        $verifyResult = Invoke-RestMethod -Uri "$baseUrl/auth/verify-otp" -Method Post -ContentType "application/json" -Body $verifyBody
        Write-Host "Success: OTP verification complete" -ForegroundColor Green
        Write-Host "  Verified: $($verifyResult.verified)" -ForegroundColor Gray
        Write-Host ""
    } catch {
        Write-Host "Failed: OTP verification error: $_" -ForegroundColor Red
        Write-Host "  This is expected if the OTP is incorrect" -ForegroundColor Gray
        Write-Host ""
    }

    # Test 4: Create Account
    Write-Host "Test 4: Creating account..." -ForegroundColor Yellow
    try {
        $password = "test123456"
        $createBody = @{ email = $testEmail; password = $password } | ConvertTo-Json
        $createResult = Invoke-RestMethod -Uri "$baseUrl/auth/create-account" -Method Post -ContentType "application/json" -Body $createBody
        Write-Host "Success: Account creation complete" -ForegroundColor Green
        Write-Host "  User ID: $($createResult.user.id)" -ForegroundColor Gray
        Write-Host "  Email: $($createResult.user.email)" -ForegroundColor Gray
        Write-Host "  Created: $($createResult.user.createdAt)" -ForegroundColor Gray
        Write-Host ""

        # Test 5: Check Email Again (Should exist now)
        Write-Host "Test 5: Checking if email exists (should be true now)..." -ForegroundColor Yellow
        try {
            $checkBody2 = @{ email = $testEmail } | ConvertTo-Json
            $checkResult2 = Invoke-RestMethod -Uri "$baseUrl/auth/check-email" -Method Post -ContentType "application/json" -Body $checkBody2
            Write-Host "Success: Email check complete" -ForegroundColor Green
            Write-Host "  Exists: $($checkResult2.exists)" -ForegroundColor Gray
            Write-Host "  Requires Password: $($checkResult2.requiresPassword)" -ForegroundColor Gray
            Write-Host ""
        } catch {
            Write-Host "Failed: Email check error: $_" -ForegroundColor Red
        }

        # Test 6: Login with Password
        Write-Host "Test 6: Logging in with password..." -ForegroundColor Yellow
        try {
            $loginBody = @{ email = $testEmail; password = $password } | ConvertTo-Json
            $loginResult = Invoke-RestMethod -Uri "$baseUrl/auth/login" -Method Post -ContentType "application/json" -Body $loginBody
            Write-Host "Success: Login complete" -ForegroundColor Green
            Write-Host "  User ID: $($loginResult.user.id)" -ForegroundColor Gray
            Write-Host "  Email: $($loginResult.user.email)" -ForegroundColor Gray
            Write-Host ""
        } catch {
            Write-Host "Failed: Login error: $_" -ForegroundColor Red
        }

        # Test 7: Login with Wrong Password
        Write-Host "Test 7: Testing login with wrong password (should fail)..." -ForegroundColor Yellow
        try {
            $wrongLoginBody = @{ email = $testEmail; password = "wrongpassword" } | ConvertTo-Json
            $wrongLoginResult = Invoke-RestMethod -Uri "$baseUrl/auth/login" -Method Post -ContentType "application/json" -Body $wrongLoginBody
            Write-Host "Failed: This should have been rejected!" -ForegroundColor Red
        } catch {
            Write-Host "Success: Correctly rejected wrong password" -ForegroundColor Green
            Write-Host ""
        }

    } catch {
        Write-Host "Failed: Account creation error: $_" -ForegroundColor Red
        Write-Host "  This might be because OTP was not verified" -ForegroundColor Gray
        Write-Host ""
    }
} else {
    Write-Host "Skipping verification tests" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "=== Test Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Test Email: $testEmail" -ForegroundColor Gray
Write-Host "  Backend URL: $baseUrl" -ForegroundColor Gray
Write-Host ""
Write-Host "To test the full flow:" -ForegroundColor Yellow
Write-Host "  1. Run the Flutter app" -ForegroundColor Gray
Write-Host "  2. Navigate to the More page" -ForegroundColor Gray
Write-Host "  3. Enter an email in the Account section" -ForegroundColor Gray
Write-Host "  4. Follow the on-screen prompts" -ForegroundColor Gray
Write-Host ""

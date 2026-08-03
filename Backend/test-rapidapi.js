const axios = require('axios');

// Test both RapidAPI endpoints
async function testRapidAPIs() {
  const apiKey = '353911e03dmshfc92380284fba44p164b70jsnba7769ba4608';
  
  // Test Spotify URL (a popular song)
  const testUrl = 'https://open.spotify.com/track/3n3Ppam7vgaVa1iaRUc9Lp'; // Mr. Brightside
  
  console.log('\n=== Testing RapidAPI Endpoints ===\n');
  
  // Test 1: DS RapidAPI (spotify-and-deezer-download)
  console.log('🔵 Test 1: DS RapidAPI (spotify-and-deezer-download)');
  try {
    const encodedUrl = encodeURIComponent(testUrl);
    const response = await axios.get(
      `https://spotify-and-deezer-download.p.rapidapi.com/api/music?url=${encodedUrl}`,
      {
        headers: {
          'x-rapidapi-key': apiKey,
          'x-rapidapi-host': 'spotify-and-deezer-download.p.rapidapi.com'
        },
        timeout: 15000
      }
    );
    
    console.log('✅ DS RapidAPI Status:', response.status);
    console.log('Response:', JSON.stringify(response.data, null, 2));
  } catch (err) {
    console.log('❌ DS RapidAPI Error:', err.response?.status || err.code);
    console.log('Error message:', err.response?.data || err.message);
    if (err.response?.headers) {
      console.log('Rate limit headers:', {
        'x-ratelimit-requests-limit': err.response.headers['x-ratelimit-requests-limit'],
        'x-ratelimit-requests-remaining': err.response.headers['x-ratelimit-requests-remaining']
      });
    }
  }
  
  console.log('\n---\n');
  
  // Test 2: Original RapidAPI (spotify-downloader9)
  console.log('🚀 Test 2: Original RapidAPI (spotify-downloader9)');
  try {
    const encodedUrl = encodeURIComponent(testUrl);
    const response = await axios.get(
      `https://spotify-downloader9.p.rapidapi.com/downloadSong?songId=${encodedUrl}`,
      {
        headers: {
          'x-rapidapi-key': apiKey,
          'x-rapidapi-host': 'spotify-downloader9.p.rapidapi.com'
        },
        timeout: 15000
      }
    );
    
    console.log('✅ Original RapidAPI Status:', response.status);
    console.log('Response:', JSON.stringify(response.data, null, 2));
  } catch (err) {
    console.log('❌ Original RapidAPI Error:', err.response?.status || err.code);
    console.log('Error message:', err.response?.data || err.message);
    if (err.response?.headers) {
      console.log('Rate limit headers:', {
        'x-ratelimit-requests-limit': err.response.headers['x-ratelimit-requests-limit'],
        'x-ratelimit-requests-remaining': err.response.headers['x-ratelimit-requests-remaining']
      });
    }
  }
  
  console.log('\n=== Test Complete ===\n');
}

testRapidAPIs().catch(console.error);

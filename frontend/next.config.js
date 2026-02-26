/** @type {import('next').NextConfig} */
const nextConfig = {
    output: 'standalone',
    env: {
        NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL || 'https://devops-backend-mmmj.onrender.com',
    },
}

module.exports = nextConfig

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  async redirects() {
    return [
      {
        source: "/privacidade",
        destination: "/politica-de-privacidade#exclusao-conta",
        permanent: false,
      },
    ];
  },
};

module.exports = nextConfig;

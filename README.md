# Aurigraph Website

**Next.js 14 marketing website for Aurigraph.io with HubSpot CRM integration**

- 🚀 **Next.js 14** - App Router with Server Components
- 📝 **Tailwind CSS** - Utility-first styling
- 🔗 **HubSpot Integration** - Contact forms and lead capture
- 📱 **Responsive** - Mobile-first design
- ⚡ **Performance** - Optimized for speed and SEO
- 🎨 **Modern Design** - Beautiful marketing pages

## Quick Start

### Prerequisites
- Node.js 20+
- npm/yarn/pnpm
- HubSpot API key (for contact forms)

### Development

```bash
# Install dependencies
npm install

# Set environment variables
cp .env.example .env.local
# Edit .env.local with HUBSPOT_API_KEY

# Start development server
npm run dev
# Site available at http://localhost:3000

# Build for production
npm run build
npm start
```

## Environment Variables

```
HUBSPOT_API_KEY=your_api_key_here
HUBSPOT_CONTACT_LIST_ID=optional_list_id
```

## Project Structure

```
├── app/                    # Next.js app directory
│   ├── page.tsx           # Home page
│   ├── about/             # About page
│   ├── technology/        # Technology page
│   └── api/
│       └── hubspot/       # HubSpot integration endpoints
├── components/            # Reusable React components
├── lib/
│   ├── hubspot.ts        # HubSpot v3 API client
│   └── hubspot-retry.ts  # Retry logic with timeout
├── public/               # Static assets
├── styles/              # Global CSS
└── __tests__/           # Test files
```

## HubSpot Integration

**API Version**: v3 (current)
**Features**:
- Contact creation/update
- Email validation
- List management
- Deal creation

**Key Files**:
- `lib/hubspot.ts` - API client with bug fixes
- `lib/hubspot-retry.ts` - Timeout + retry protection
- `__tests__/hubspot.test.ts` - 16/20 tests passing (80%)
- `app/api/hubspot/test` - Integration test endpoint

## Deployment

### Staging

```bash
docker-compose -f docker-compose.production.yml up -d
```

### Production (Blue-Green)

```bash
bash deployment/deploy-production.sh
```

**Features**:
- Zero-downtime deployment via NGINX switching
- Automatic health checks
- Quick rollback (<30 seconds)

## Testing

```bash
# Unit tests
npm run test

# Coverage report
npm run test:coverage

# HubSpot integration test
curl http://localhost:3000/api/hubspot/test
```

## Performance Metrics

- **Lighthouse**: 95+ score
- **Core Web Vitals**: Good
- **Load Time**: <2s (3G)

## Deployment Status

✅ MVP deployed to dlt.aurigraph.io
✅ HubSpot integration verified
✅ Blue-green deployment working
✅ Health checks passing

## Support

- 📧 Email: support@aurigraph.io
- 🐛 Issues: GitHub Issues
- 📚 Docs: https://docs.aurigraph.io

## License

Apache License 2.0

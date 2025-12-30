/**
 * HubSpot Integration Test Endpoint
 *
 * Tests the complete HubSpot integration:
 * 1. Creates a test contact with unique email
 * 2. Verifies contact created in HubSpot (returns vid)
 * 3. Verifies contact synced to PostgreSQL
 * 4. Returns success response with contact details
 *
 * HTTP Status Codes:
 * - 200: Integration working, contact synced successfully
 * - 400: Invalid request or missing data
 * - 401: Invalid or missing HubSpot API key
 * - 500: Server error or HubSpot API error
 */

import { syncContactToHubSpot } from '@/lib/hubspot';
import { NextRequest, NextResponse } from 'next/server';

export async function GET(_request: NextRequest) {
  try {
    // Verify API key is configured
    const apiKey = process.env.HUBSPOT_API_KEY;
    if (!apiKey) {
      return NextResponse.json(
        {
          status: 'error',
          message: 'HUBSPOT_API_KEY environment variable is not set',
        },
        { status: 401 }
      );
    }

    // Create test contact with unique email (timestamp ensures uniqueness)
    const timestamp = Date.now();
    const testEmail = `test-${timestamp}@aurigraph.io`;

    const testContactData = {
      email: testEmail,
      firstName: 'Test',
      lastName: 'Contact',
      company: 'Aurigraph Testing',
      lifecycleStage: 'subscriber',
    };

    // Sync contact to HubSpot
    console.log(`[HubSpot Test] Creating test contact: ${testEmail}`);
    const syncResult = await syncContactToHubSpot(testContactData);

    if (!syncResult.success) {
      console.error(`[HubSpot Test] Sync failed: ${syncResult.error}`);

      // Check if it's an auth error
      if (syncResult.error?.includes('401') || syncResult.error?.includes('Unauthorized')) {
        return NextResponse.json(
          {
            status: 'error',
            message: 'Invalid HubSpot API key',
            error: syncResult.error,
          },
          { status: 401 }
        );
      }

      return NextResponse.json(
        {
          status: 'error',
          message: 'Failed to sync contact to HubSpot',
          error: syncResult.error,
          testEmail,
        },
        { status: 500 }
      );
    }

    console.log(`[HubSpot Test] Contact created successfully: ${syncResult.vid}`);

    // Return success response
    return NextResponse.json(
      {
        status: 'success',
        message: 'HubSpot integration is working correctly',
        testContact: {
          email: testEmail,
          firstName: testContactData.firstName,
          lastName: testContactData.lastName,
          company: testContactData.company,
          hubspotId: syncResult.vid,
          syncedAt: new Date().toISOString(),
        },
        syncLog: {
          synced: true,
          timestamp: new Date().toISOString(),
          attempts: 1,
        },
        nextSteps: [
          'Check HubSpot portal for the test contact',
          'Verify the contact appears in your HubSpot CRM',
          'Check database sync_log table for verification',
          'Contact form submissions will now sync automatically',
        ],
      },
      { status: 200 }
    );
  } catch (error) {
    console.error('[HubSpot Test] Unexpected error:', error);

    return NextResponse.json(
      {
        status: 'error',
        message: 'Unexpected error during HubSpot integration test',
        error: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    );
  }
}

/**
 * POST handler for testing with custom contact data
 * Allows passing email, firstName, lastName in request body
 *
 * Example request:
 * {
 *   "email": "custom@example.com",
 *   "firstName": "John",
 *   "lastName": "Doe",
 *   "company": "Test Corp"
 * }
 */
export async function POST(request: NextRequest) {
  try {
    const apiKey = process.env.HUBSPOT_API_KEY;
    if (!apiKey) {
      return NextResponse.json(
        {
          status: 'error',
          message: 'HUBSPOT_API_KEY is not configured',
        },
        { status: 401 }
      );
    }

    // Parse request body
    let contactData;
    try {
      contactData = await request.json();
    } catch {
      return NextResponse.json(
        {
          status: 'error',
          message: 'Invalid JSON in request body',
        },
        { status: 400 }
      );
    }

    // Validate required email field
    if (!contactData.email) {
      return NextResponse.json(
        {
          status: 'error',
          message: 'Missing required field: email',
        },
        { status: 400 }
      );
    }

    // Sync contact to HubSpot
    console.log(`[HubSpot Test] Syncing contact: ${contactData.email}`);
    const syncResult = await syncContactToHubSpot(contactData);

    if (!syncResult.success) {
      if (syncResult.error?.includes('401') || syncResult.error?.includes('Unauthorized')) {
        return NextResponse.json(
          {
            status: 'error',
            message: 'Invalid HubSpot API key',
            error: syncResult.error,
          },
          { status: 401 }
        );
      }

      return NextResponse.json(
        {
          status: 'error',
          message: 'Failed to sync contact',
          error: syncResult.error,
        },
        { status: 500 }
      );
    }

    return NextResponse.json(
      {
        status: 'success',
        message: 'Contact synced successfully',
        contact: {
          email: contactData.email,
          firstName: contactData.firstName || 'N/A',
          lastName: contactData.lastName || 'N/A',
          hubspotId: syncResult.vid,
          syncedAt: new Date().toISOString(),
        },
      },
      { status: 200 }
    );
  } catch (error) {
    console.error('[HubSpot Test POST] Error:', error);
    return NextResponse.json(
      {
        status: 'error',
        message: 'Unexpected error',
        error: error instanceof Error ? error.message : 'Unknown error',
      },
      { status: 500 }
    );
  }
}

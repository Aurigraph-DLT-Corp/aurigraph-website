import { Pool } from 'pg';
import { NextRequest, NextResponse } from 'next/server';
import { syncContactToHubSpot, logActivityToHubSpot } from '@/lib/hubspot';

// Initialize PostgreSQL connection pool
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

interface ContactFormData {
  name: string;
  email: string;
  company?: string;
  useCase?: string;
  message: string;
}

interface ContactFormRequest extends NextRequest {
  json(): Promise<ContactFormData>;
}

/**
 * POST /api/contact
 * Saves contact form submissions to PostgreSQL and syncs to HubSpot
 */
export async function POST(request: ContactFormRequest) {
  let client = null;

  try {
    // Parse request body
    const body: ContactFormData = await request.json();

    // Validate required fields
    const { name, email, company, useCase, message } = body;

    if (!name || !email || !message) {
      return NextResponse.json(
        { error: 'Missing required fields: name, email, message' },
        { status: 400 }
      );
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return NextResponse.json(
        { error: 'Invalid email address' },
        { status: 400 }
      );
    }

    // Split name into first and last
    const nameParts = name.trim().split(/\s+/);
    const firstName = nameParts[0];
    const lastName = nameParts.slice(1).join(' ') || '';

    // Insert into database
    client = await pool.connect();

    // Save to PostgreSQL
    const result = await client.query(
      `INSERT INTO website.contact_submissions (name, email, company, use_case, message, status)
       VALUES ($1, $2, $3, $4, $5, 'new')
       RETURNING id, created_at`,
      [name, email, company || null, useCase || null, message]
    );

    const submissionId = result.rows[0].id;
    const createdAt = result.rows[0].created_at;

    // Update analytics
    await client.query(
      `INSERT INTO website.form_analytics (form_name, submission_date, total_submissions, successful_submissions)
       VALUES ('contact', CURRENT_DATE, 1, 1)
       ON CONFLICT (form_name, submission_date) DO UPDATE SET
         total_submissions = total_submissions + 1,
         successful_submissions = successful_submissions + 1,
         updated_at = CURRENT_TIMESTAMP`
    );

    // Sync to HubSpot in background (don't block response)
    syncContactToHubSpotAsync(client, submissionId, {
      firstName,
      lastName,
      email,
      company: company || '',
      useCase: useCase || '',
      message,
    });

    // Send notification email (optional)
    if (process.env.ADMIN_EMAIL && process.env.NEXT_PUBLIC_SMTP_PASSWORD) {
      try {
        await sendAdminNotification({
          submissionId,
          name,
          email,
          company,
          useCase,
          message,
        });
      } catch (emailError) {
        console.error('Failed to send admin notification:', emailError);
        // Continue despite email failure
      }
    }

    return NextResponse.json(
      {
        success: true,
        message:
          'Thank you! Your message has been received. We will get back to you soon.',
        submissionId,
        createdAt,
      },
      { status: 201 }
    );
  } catch (error) {
    console.error('Contact form error:', error);

    // Log failed submission
    if (client) {
      try {
        await client.query(
          `INSERT INTO website.form_analytics (form_name, submission_date, total_submissions, failed_submissions)
           VALUES ('contact', CURRENT_DATE, 1, 1)
           ON CONFLICT (form_name, submission_date) DO UPDATE SET
             total_submissions = total_submissions + 1,
             failed_submissions = failed_submissions + 1,
             updated_at = CURRENT_TIMESTAMP`
        );
      } catch (analyticsError) {
        console.error('Failed to log analytics:', analyticsError);
      }
    }

    return NextResponse.json(
      {
        success: false,
        error: 'Failed to process your request. Please try again later.',
      },
      { status: 500 }
    );
  } finally {
    if (client) {
      client.release();
    }
  }
}

/**
 * GET /api/contact/status
 * Check database and HubSpot connectivity
 */
export async function GET() {
  try {
    const client = await pool.connect();

    // Check database
    const dbResult = await client.query('SELECT NOW()');
    client.release();

    // Check HubSpot API key
    const hubspotKey = process.env.HUBSPOT_API_KEY ? 'configured' : 'not configured';

    return NextResponse.json(
      {
        status: 'healthy',
        database: 'connected',
        hubspot: hubspotKey,
        timestamp: dbResult.rows[0].now,
      },
      { status: 200 }
    );
  } catch (error) {
    console.error('Health check failed:', error);
    return NextResponse.json(
      {
        status: 'unhealthy',
        database: 'disconnected',
        error: String(error),
      },
      { status: 503 }
    );
  }
}

/**
 * Async HubSpot sync (non-blocking)
 */
async function syncContactToHubSpotAsync(
  client: any,
  submissionId: number,
  contactData: {
    firstName: string;
    lastName: string;
    email: string;
    company: string;
    useCase: string;
    message: string;
  }
) {
  try {
    // Sync to HubSpot
    const hubspotResult = await syncContactToHubSpot({
      email: contactData.email,
      firstName: contactData.firstName,
      lastName: contactData.lastName,
      company: contactData.company,
      lifecycleStage: 'lead',
      source: 'website-contact-form',
      customFields: {
        hs_use_case: contactData.useCase,
        hs_message: contactData.message,
      },
    });

    // Log sync result
    if (hubspotResult.success) {
      // Update contact submission with HubSpot ID
      await client.query(
        `UPDATE website.contact_submissions
         SET hubspot_synced = TRUE,
             hubspot_contact_id = $1,
             synced_at = CURRENT_TIMESTAMP
         WHERE id = $2`,
        [hubspotResult.vid, submissionId]
      );

      // Log successful sync
      await client.query(
        `INSERT INTO website.hubspot_sync_log (contact_id, email, sync_type, success, hubspot_response)
         VALUES ($1, $2, 'create', TRUE, $3)`,
        [submissionId, contactData.email, JSON.stringify(hubspotResult)]
      );

      // Update analytics
      await client.query(
        `UPDATE website.form_analytics
         SET hubspot_synced_count = hubspot_synced_count + 1,
             updated_at = CURRENT_TIMESTAMP
         WHERE form_name = 'contact' AND submission_date = CURRENT_DATE`
      );

      console.log(`✅ HubSpot sync successful for ${contactData.email}`);
    } else {
      // Log failed sync
      await client.query(
        `INSERT INTO website.hubspot_sync_log (contact_id, email, sync_type, success, error_message)
         VALUES ($1, $2, 'create', FALSE, $3)`,
        [submissionId, contactData.email, hubspotResult.error]
      );

      console.error(`❌ HubSpot sync failed for ${contactData.email}: ${hubspotResult.error}`);
    }

    // Log activity to HubSpot
    await logActivityToHubSpot({
      email: contactData.email,
      activityType: 'contact_form_submission',
      activityText: `Contact form submission from ${contactData.firstName} ${contactData.lastName}\n\nUse Case: ${contactData.useCase}\n\nMessage: ${contactData.message}`,
    });
  } catch (error) {
    console.error('HubSpot sync error:', error);

    // Log the error
    try {
      await client.query(
        `INSERT INTO website.hubspot_sync_log (contact_id, email, sync_type, success, error_message)
         VALUES ($1, $2, 'create', FALSE, $3)`,
        [submissionId, contactData.email, String(error)]
      );
    } catch (logError) {
      console.error('Failed to log HubSpot sync error:', logError);
    }
  }
}

/**
 * Send email notification to admin
 */
async function sendAdminNotification(data: {
  submissionId: number;
  name: string;
  email: string;
  company?: string;
  useCase?: string;
  message: string;
}) {
  const { name, email, company, useCase, message, submissionId } = data;

  // Build email content
  const emailContent = `
New Contact Form Submission (#${submissionId})

Name: ${name}
Email: ${email}
Company: ${company || 'N/A'}
Use Case: ${useCase || 'N/A'}

Message:
${message}

---
View this submission: https://aurigraph.io/admin/submissions/${submissionId}
HubSpot: https://app.hubspot.com/contacts/main/contacts/search?q=${encodeURIComponent(email)}
  `.trim();

  // Send via SendGrid (optional)
  try {
    const sgMail = await import('@sendgrid/mail').then(m => m.default);
    sgMail.setApiKey(process.env.NEXT_PUBLIC_SMTP_PASSWORD || '');

    await sgMail.send({
      to: process.env.ADMIN_EMAIL!,
      from: 'noreply@aurigraph.io',
      subject: `New Contact Form Submission from ${name}`,
      text: emailContent,
      html: `<pre>${emailContent}</pre>`,
    });
  } catch (error) {
    console.error('SendGrid email error:', error);
    // Silently fail - don't block form submission
  }
}

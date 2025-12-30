/**
 * HubSpot CRM Integration
 * Syncs contact form submissions and user registrations to HubSpot
 */

import { fetchWithRetry } from './hubspot-retry';

interface HubSpotContact {
  email: string;
  firstName?: string;
  lastName?: string;
  company?: string;
  lifecycleStage?: string;
  source?: string;
  customFields?: Record<string, string>;
}

interface HubSpotResponse {
  vid?: number;
  portalId?: number;
  isContact?: boolean;
  portalHasBeenOnboarded?: boolean;
  profileToken?: string;
  profileUrl?: string;
  userToken?: string | null;
  identityProfiles?: Array<{
    vid: number;
    deletedAt: number;
    identities: Array<{
      type: string;
      value: string;
    }>;
    isContact: boolean;
  }>;
  [key: string]: unknown;
}

/**
 * Initialize HubSpot API client
 */
function getHubSpotApiKey(): string {
  const apiKey = process.env.HUBSPOT_API_KEY;
  if (!apiKey) {
    throw new Error('HUBSPOT_API_KEY environment variable is not set');
  }
  return apiKey;
}

/**
 * Create or update contact in HubSpot
 */
export async function syncContactToHubSpot(
  contactData: HubSpotContact
): Promise<{ success: boolean; vid?: number; error?: string }> {
  try {
    const apiKey = getHubSpotApiKey();

    // Prepare properties for HubSpot
    const properties = [
      { property: 'email', value: contactData.email },
      { property: 'firstname', value: contactData.firstName || '' },
      { property: 'lastname', value: contactData.lastName || '' },
      { property: 'company', value: contactData.company || '' },
      { property: 'lifecyclestage', value: contactData.lifecycleStage || 'subscriber' },
      { property: 'hs_lead_status', value: 'NEW' },
    ];

    // Add custom fields if provided
    if (contactData.customFields) {
      Object.entries(contactData.customFields).forEach(([key, value]) => {
        properties.push({ property: key, value });
      });
    }

    // Check if contact exists
    const existingContact = await getContactByEmail(contactData.email, apiKey);

    if (existingContact?.vid) {
      // Update existing contact
      return await updateContact(existingContact.vid, properties, apiKey);
    } else {
      // Create new contact
      return await createContact(properties, apiKey);
    }
  } catch (error) {
    console.error('HubSpot sync error:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

/**
 * Get contact by email (using efficient Search API)
 */
async function getContactByEmail(
  email: string,
  apiKey: string
): Promise<HubSpotResponse | null> {
  try {
    const response = await fetchWithRetry(
      'https://api.hubapi.com/crm/v3/objects/contacts/search',
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          filterGroups: [
            {
              filters: [
                {
                  propertyName: 'email',
                  operator: 'EQ',
                  value: email,
                },
              ],
            },
          ],
          limit: 1,
          sorts: [{ propertyName: 'hs_object_id', direction: 'DESCENDING' }],
        }),
      }
    );

    if (!response.ok) {
      return null;
    }

    const data = await response.json();
    const contacts = data.results || [];

    // Return the first contact (or null if not found)
    return contacts.length > 0 ? contacts[0] : null;
  } catch (error) {
    console.error('Error fetching contact from HubSpot:', error);
    return null;
  }
}

/**
 * Create new contact in HubSpot
 */
async function createContact(
  properties: Array<{ property: string; value: string }>,
  apiKey: string
): Promise<{ success: boolean; vid?: number; error?: string }> {
  try {
    const response = await fetchWithRetry('https://api.hubapi.com/crm/v3/objects/contacts', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        properties: properties.reduce((acc, p) => ({
          ...acc,
          [p.property]: p.value,
        }), {}),
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      return {
        success: false,
        error: error.message || 'Failed to create contact',
      };
    }

    const data = await response.json();
    return {
      success: true,
      vid: data.id,
    };
  } catch (error) {
    console.error('Error creating contact in HubSpot:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

/**
 * Update existing contact in HubSpot
 */
async function updateContact(
  vid: number,
  properties: Array<{ property: string; value: string }>,
  apiKey: string
): Promise<{ success: boolean; vid?: number; error?: string }> {
  try {
    const response = await fetchWithRetry(`https://api.hubapi.com/crm/v3/objects/contacts/${vid}`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        properties: properties.reduce((acc, p) => ({
          ...acc,
          [p.property]: p.value,
        }), {}),
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      return {
        success: false,
        error: error.message || 'Failed to update contact',
      };
    }

    return {
      success: true,
      vid,
    };
  } catch (error) {
    console.error('Error updating contact in HubSpot:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

/**
 * Add contact to HubSpot list
 */
export async function addContactToList(
  email: string,
  listId: string
): Promise<{ success: boolean; error?: string }> {
  try {
    const apiKey = getHubSpotApiKey();

    const response = await fetchWithRetry(
      `https://api.hubapi.com/crm/v3/lists/${listId}/members`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          emails: [email],
        }),
      }
    );

    if (!response.ok) {
      const error = await response.json();
      return {
        success: false,
        error: error.message || 'Failed to add contact to list',
      };
    }

    return { success: true };
  } catch (error) {
    console.error('Error adding contact to HubSpot list:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

/**
 * Create HubSpot deal (for sales pipeline)
 */
export async function createHubSpotDeal(data: {
  contactEmail: string;
  dealName: string;
  dealStage?: string;
  dealAmount?: number;
  properties?: Record<string, string>;
}): Promise<{ success: boolean; dealId?: string; error?: string }> {
  try {
    const apiKey = getHubSpotApiKey();

    const response = await fetchWithRetry('https://api.hubapi.com/crm/v3/objects/deals', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        properties: [
          { name: 'dealname', value: data.dealName },
          { name: 'dealstage', value: data.dealStage || 'negotiation' },
          { name: 'amount', value: String(data.dealAmount || 0) },
          ...(data.properties
            ? Object.entries(data.properties).map(([k, v]) => ({
                name: k,
                value: v,
              }))
            : []),
        ],
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      return {
        success: false,
        error: error.message || 'Failed to create deal',
      };
    }

    const result = await response.json();
    return {
      success: true,
      dealId: result.id,
    };
  } catch (error) {
    console.error('Error creating HubSpot deal:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

/**
 * Log activity to HubSpot (contact form submission, etc.)
 */
export async function logActivityToHubSpot(data: {
  email: string;
  activityType: string;
  activityText: string;
}): Promise<{ success: boolean; error?: string }> {
  try {
    const apiKey = getHubSpotApiKey();

    // First, get the contact
    const contact = await getContactByEmail(data.email, apiKey);
    if (!contact?.vid) {
      return {
        success: false,
        error: 'Contact not found in HubSpot',
      };
    }

    // Create engagement
    const response = await fetchWithRetry('https://api.hubapi.com/crm/v3/objects/notes', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        properties: [
          { name: 'hs_note_body', value: data.activityText },
          { name: 'hs_activity_type', value: data.activityType },
        ],
        associations: [
          {
            types: [{ associationCategory: 'HUBSPOT_DEFINED', associationTypeId: 5 }],
            id: contact.vid,
          },
        ],
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      return {
        success: false,
        error: error.message || 'Failed to log activity',
      };
    }

    return { success: true };
  } catch (error) {
    console.error('Error logging activity to HubSpot:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

// Firebase Cloud Messaging (HTTP v1): one notification to one device.

export interface PushMessage {
  title: string;
  body: string;
  /** In-app route opened when the notification is tapped. */
  route: string;
  /** Android channel the app creates (due_reminders). */
  channel: string;
  /** Same tag replaces the earlier notification instead of stacking another. */
  tag?: string;
}

export type PushResult = 'sent' | 'gone' | 'failed';

export class Push {
  constructor(
    private readonly projectId: string,
    private readonly token: () => Promise<string>,
    private readonly fetchImpl: typeof fetch = fetch,
    private readonly baseUrl = 'https://fcm.googleapis.com',
  ) {}

  /** 'gone' means the device token is no longer valid and should be forgotten. */
  async send(deviceToken: string, m: PushMessage): Promise<PushResult> {
    const res = await this.fetchImpl(`${this.baseUrl}/v1/projects/${this.projectId}/messages:send`, {
      method: 'POST',
      headers: { authorization: `Bearer ${await this.token()}`, 'content-type': 'application/json' },
      body: JSON.stringify({
        message: {
          token: deviceToken,
          notification: { title: m.title, body: m.body },
          data: { route: m.route },
          android: {
            priority: 'HIGH',
            notification: {
              channel_id: m.channel,
              ...(m.tag ? { tag: m.tag } : {}),
              click_action: 'FLUTTER_NOTIFICATION_CLICK',
              // The status-bar silhouette and the brand indigo that tints it.
              icon: 'ic_stat_due',
              color: '#4F46E5',
            },
          },
        },
      }),
    });
    if (res.ok) return 'sent';
    const text = await res.text();
    if (res.status === 404 || /UNREGISTERED|registration-token-not-registered/i.test(text)) return 'gone';
    if (res.status === 400 && /INVALID_ARGUMENT/.test(text) && /token/i.test(text)) return 'gone';
    console.warn(`push failed ${res.status}: ${text.slice(0, 200)}`);
    return 'failed';
  }
}

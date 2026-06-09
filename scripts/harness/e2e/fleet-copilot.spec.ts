import { test, expect } from '@playwright/test';

test.describe('Fleet Copilot smoke (T-328)', () => {
  test('nav Copilot + locked without session', async ({ page }) => {
    await page.route('**/api/fleet/copilot/session', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ authenticated: false, enabled: true }),
      });
    });
    await page.goto('/#fleet-copilot');
    await expect(page.getByRole('heading', { name: /Fleet Copilot/i })).toBeVisible();
    await expect(page.getByText('Sessão necessária')).toBeVisible();
  });

  test('mock SSE preset flow', async ({ page }) => {
    await page.route('**/api/fleet/copilot/session', async (route) => {
      await route.fulfill({ json: { authenticated: true, enabled: true } });
    });
    await page.route('**/api/fleet/chat/stream', async (route) => {
      const body =
        'event: phase\ndata: {"phase":"infer"}\n\n' +
        'event: done\ndata: {"reply":"Hosts: OCI, SSDNodes, Hetzner, AWS.","model":"fleet-manifest","sources":["fleet_manifest"],"latency_ms":42}\n\n';
      await route.fulfill({
        status: 200,
        headers: { 'Content-Type': 'text/event-stream' },
        body,
      });
    });
    await page.goto('/#fleet-copilot');
    await page.getByRole('textbox', { name: 'Mensagem' }).fill('Quais hosts?');
    await page.getByRole('button', { name: 'Enviar' }).click();
    await expect(page.getByText('Hosts: OCI, SSDNodes')).toBeVisible({ timeout: 15_000 });
  });
});

export async function adminLogin() {
  const result = await fetch(
    "http://keycloak.localtest.me:9081/auth/realms/master/protocol/openid-connect/token",
    {
      method: "POST",
      body: "grant_type=password&client_id=admin-cli&username=local&password=local",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
    }
  ).then((response) => response.json());
  return result.access_token;
}

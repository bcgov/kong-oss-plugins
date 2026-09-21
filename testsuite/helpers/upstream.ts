export const upstream = {
  host: "upstream.localtest.me",
  port: 80,
  protocol: "http" as const,
};

export const upstreamServiceDefaults = {
  host: upstream.host,
  port: upstream.port,
  protocol: upstream.protocol,
};

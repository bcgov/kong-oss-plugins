if ((process.env.KONG_VERSION || "").startsWith("2.")) {
  console.log("K2");
  return;
}

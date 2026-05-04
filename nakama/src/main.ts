function rpcHealthcheck(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  return JSON.stringify({
    ok: true,
    service: "sprint-nakama",
    userId: ctx.userId || null
  });
}

function InitModule(
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  initializer: nkruntime.Initializer
): void {
  initializer.registerRpc("healthcheck", rpcHealthcheck);
  logger.info("Sprint Nakama runtime initialized.");
}

/// Build-time client configuration.
///
/// Override values with `--dart-define`. The defaults target the local Docker
/// stack from an Android emulator and are not production credentials.
const googleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue:
      '481929024343-f6ar478mu0uconqjospg3ijps85uavd1.apps.googleusercontent.com',
);

const nakamaHost = String.fromEnvironment(
  'NAKAMA_HOST',
  defaultValue: '10.0.2.2',
);
const nakamaGrpcPort = int.fromEnvironment(
  'NAKAMA_GRPC_PORT',
  defaultValue: 7349,
);
const nakamaHttpPort = int.fromEnvironment(
  'NAKAMA_HTTP_PORT',
  defaultValue: 7350,
);
const nakamaServerKey = String.fromEnvironment(
  'NAKAMA_SERVER_KEY',
  defaultValue: 'defaultkey',
);
const nakamaUseSsl = bool.fromEnvironment(
  'NAKAMA_USE_SSL',
  defaultValue: false,
);

const playerProfileCollection = 'player';
const playerProfileKey = 'profile';

const sprintMatchmakerQuery = '*';
const sprintMatchmakerMode = 'sprint_quickplay';

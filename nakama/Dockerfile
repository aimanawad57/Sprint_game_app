FROM node:22-alpine AS node-builder

WORKDIR /backend

RUN apk add --no-cache git

COPY package*.json .
RUN npm install

COPY tsconfig.json .
COPY src/ src/
RUN npx tsc

FROM heroiclabs/nakama:3.22.0

COPY --from=node-builder /backend/build/*.js /nakama/data/modules/build/
COPY local.yml /nakama/data/

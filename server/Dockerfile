FROM node:22-alpine
WORKDIR /app
COPY beamx-signal.mjs .
USER node
ENV PORT=8080 DATA_DIR=/data
EXPOSE 8080
CMD ["node", "beamx-signal.mjs"]

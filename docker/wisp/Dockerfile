FROM node:24-alpine

ARG WISP_JS_VERSION=0.4.1

RUN npm install -g --no-fund --no-audit "@mercuryworkshop/wisp-js@${WISP_JS_VERSION}"

COPY entrypoint.sh /usr/local/bin/wisp-entrypoint
RUN chmod +x /usr/local/bin/wisp-entrypoint

EXPOSE 5001

ENTRYPOINT ["/usr/local/bin/wisp-entrypoint"]

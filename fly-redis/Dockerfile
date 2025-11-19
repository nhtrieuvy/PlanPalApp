FROM redis:7-alpine

# Expose Redis port
EXPOSE 6379

# Data persistence
VOLUME /data

# Use appendonly for data persistence
CMD ["redis-server", "--appendonly", "yes"]

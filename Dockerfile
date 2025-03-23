# Base stage - Build React App
FROM node:18-alpine AS build
WORKDIR /app

# Copy package.json and package-lock.json for better caching
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy the source files
COPY . .

# COPY ./src/ .

# ADD ./public/ .

# Build the React application
RUN npm run build

# Final stage - Serve with Nginx
FROM nginx:1.25.3-alpine
COPY --from=build /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf

# Expose port 80 for web traffic
EXPOSE 3000

# Start Nginx server
CMD ["nginx", "-g", "daemon off;"]

# Use the official apache image as a base
FROM httpd:latest

# Copy the frontend code to the container
COPY ./public/ /usr/local/apache2/htdocs/
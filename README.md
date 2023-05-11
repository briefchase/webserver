# webserver
To run the server enter:
 - sudo docker run -d -p 80:80 -v $(pwd)/public:/usr/local/apache2/htdocs httpd:latest
or
 - sudo docker-compose up

 To run the server locally enter:
 - sudo docker run -d -p 8080:80 -v $(pwd)/public:/usr/local/apache2/htdocs httpd:latest
# To avoid Docker Hub rate limits, use Public ECR nginx
FROM public.ecr.aws/nginx/nginx:alpine
COPY index.html /usr/share/nginx/html/index.html

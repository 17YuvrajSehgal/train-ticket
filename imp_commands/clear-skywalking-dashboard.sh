#Port-forward Elasticsearch
kubectl port-forward pod/elasticsearch-76885bb9f7-rl5ht 9200:9200

#Check existing indices
curl http://localhost:9200/_cat/indices?v

#Delete all SkyWalking indices
curl -X DELETE "http://localhost:9200/sw_*"

#Restart SkyWalking OAP -> If that label doesn’t match, restart the exact pod you have:
#like kubectl delete pod skywalking-7d48bf46c9-qhsv5
kubectl delete pod -l app=skywalking
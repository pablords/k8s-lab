kubectl argo rollouts get rollout -n frontend nginx --watch

kubectl argo rollouts set image -n frontend nginx nginx=nginx:1.20

Promover ou Reverter:

Se a nova versão estiver funcionando corretamente, promova o Rollout:

kubectl argo rollouts promote -n frontend nginx

Se houver problemas, reverta para a versão anterior:

kubectl argo rollouts undo -n frontend nginx

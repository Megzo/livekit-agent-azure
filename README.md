# Run an AI Vocie Agent with Azure, Kubernetes and LiveKit

In this repo contains the deployment manifests to set up a LiveKit AI Agent in Azure.
We'll go through the following:
 - Set up an Azure Cognitive Services Account for deploying a Speech Service (for STT and TTS) and an OpenAI model (for LLM) using Terraform.
 - Set up a Kubernetes cluster in Azure (AKS) also using Terraform. 
 - Deploy the necessary services in Kubernetes:
   1. [STUNner](https://github.com/l7mp/stunner): as a Kubernetes gateway for the WebRTC traffic.
   2. [LiveKit Server](https://github.com/livekit/livekit): the main service that hosts the WebRTC audio/video rooms.
   3. [Demo Token Server](https://github.com/Megzo/livekit-token-generator): simple service that generates authentication tokens for LiveKit.
   4. [LiveKit Agent](https://github.com/livekit/agents): the agent itself that converts voice to text, puts the text in an LLM, and convers the answer back to voice.
   5. [Agents Playground](https://github.com/livekit/agents-playground): a prototype UI for the setup.

Read more in my [blog post](https://medium.com/@megyesi.peter.zoltan).

## 1. Set up Terraform variables

[Terraform](https://www.terraform.io/) is a great way to provision the whole infrastructure for the demo.
We'll use to create the Azure AI services, and spin up an AKS cluster to host the custom components.

First, be sure to check out `variables.tf` to customize your setup (e.g. service names, region to deploy, node sizes, etc.).

Then, install [Terraform](https://developer.hashicorp.com/terraform/install) and the [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt):
```
# install Terraform 
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# install and configure Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az login --use-device-code
```

Finally, set up and init Terraform 
```
# set up environment for Terraform
export ARM_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
terraform init
terraform apply
```

If everything went correctly, you can check your endpoints and api keys with the following commands, we'll need these when setting up the Kuberentes secrets:
```
terraform output
# api keys are reducted, so you have run this
terraform output -raw speech_key
terraform output -raw openai_key
```

Also, create the your `kubeconfig` file:
```
terraform output -raw kubeconfig > kubeconfig.yaml
export KUBECONFIG=kubeconfig.yaml
```


## 2. Set up LiveKit in Kubernetes 

With Terraform we already have an AKS cluster to deploy our service.
Check the manifests in the [`manifests/`]() folder, and modify it to your usecase.
Then follow these steps.


Install an Ingress Controller and Cert-Manager for TLS management (you could use Azure L7 load balancers as well, but I just prefer my on ingress):
```
# install nginx:
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/cloud/deploy.yaml

# install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.3/cert-manager.yaml
# wait for cert-manager to be ready...
kubectl wait --for=condition=Ready -n cert-manager pod  -l app.kubernetes.io/component=webhook --timeout=100s
# create a cluster issuer
kubectl apply -f manifests/issuer.yaml
```

Check the `External IP` of the Nginx service, and set it up in your DNS provider:
```
$ kubectl get service -n ingress-nginx
NAME                                 TYPE           CLUSTER-IP     EXTERNAL-IP    PORT(S)                      AGE
ingress-nginx-controller             LoadBalancer   10.0.148.195   9.223.58.224   80:30425/TCP,443:30526/TCP   98s
ingress-nginx-controller-admission   ClusterIP      10.0.53.20     <none>         443/TCP                      98s
```

E.g. I set up an `A` record for `*.azure.stunner.cc` to point to `9.223.58.224`.

Now, install STUNner, to serve as a WebRTC gateway. STUNner will make sure you can connect to the LiveKit server:
```
helm repo add stunner https://l7mp.io/stunner
helm repo update
helm install stunner-gateway-operator stunner/stunner-gateway-operator --create-namespace --namespace=stunner
kubectl apply -f manifests/stunner-common.yaml
```

Check the `External IP` of the `webrtc-gateway` service, we'll this as the TURN server for LiveKit (`9.223.2.106` in this example):
```
$ kubectl get service -n stunner
NAME                                                          TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)                         AGE
stunner-auth                                                  ClusterIP      10.0.172.54    <none>        8088/TCP                        90s
stunner-config-discovery                                      ClusterIP      10.0.132.227   <none>        13478/TCP                       90s
stunner-gateway-operator-controller-manager-metrics-service   ClusterIP      10.0.158.213   <none>        8443/TCP                        90s
webrtc-gateway                                                LoadBalancer   10.0.152.191   9.223.2.106   3478:30516/UDP,3478:30516/TCP   72s
```

You can also use a DNS name for this IP, but it is only mandatory if you add [TLS listeners](https://docs.l7mp.io/en/stable/GATEWAY/#listener-configuration).

Run this to save the external IP of STUNner to a env variable:
```
export TURNIP=$(kubectl get service -n stunner webrtc-gateway -o jsonpath={.status.loadBalancer.ingress[0].ip})
echo $TURNIP
```

You have to set up this IP as the TURN server for LiveKit in its configuration:
```
      turn_servers:
      - credential: pass-1
        host: 9.223.2.106
        port: 3478
        protocol: udp
        username: user-1
```

You can just execute this command to replace this inline in the LiveKit `ConfigMap`:
```
sed -i "s/9.223.2.106/$TURNIP/g" manifests/livekit.yaml
```

Next, change the domin for the one you set up in the DNS:
```
export MYDOMAIN=azure.stunner.cc
sed -i "s/azure.stunner.cc/$MYDOMAIN/g" manifests/livekit.yaml
sed -i "s/azure.stunner.cc/$MYDOMAIN/g" manifests/secret.yaml
```

Finally, you also have to modify the credentials in `manifests/secret.yaml`.
Mine looks like this:
```
apiVersion: v1
kind: Secret
metadata:
  name: livekit-agents-secrets
type: Opaque
stringData:
  LIVEKIT_URL: wss://livekit.azure.stunner.cc # match your domain
  LIVEKIT_API_KEY: access_token # match your api key
  LIVEKIT_API_SECRET: secret # match your secret
  AZURE_SPEECH_KEY: <your speech key> # terraform output -raw speech_key
  AZURE_SPEECH_REGION: swedencentral # match your Azure Region
  AZURE_OPENAI_ENDPOINT: https://swedencentral.api.cognitive.microsoft.com/openai/deployments/livekit-agent-azure-openai-model/chat/completions?api-version=2024-08-01-preview # terraform output -raw openai_endpoint check Azure AI Foundry at ai.azure.com for the your version
  AZURE_OPENAI_API_KEY: <your azure openai key> #terraform output -raw openapi_key
  OPENAI_API_VERSION: 2024-08-01-preview # check Azure AI Foundry at ai.azure.com for the your version 
```

The most trickey envs are `AZURE_OPENAI_ENDPOINT` and `OPENAI_API_VERSION`. I could not figure out how to export them using Terraform, so you might have to manually get them from [Azure AI Foundry](https://ai.azure.com).

If everything is ready, just deploy these two file:
```
kubectl apply -f manifests/secret.yaml
kubectl apply -f manifests/livekit.yaml
```

If everything went well, you should be able to go the the Agents UI using the URL you give.
In my example is: `https://agent-ui.azure.stunner.cc`.

Finally, be sure to check out [blog post](https://medium.com/@megyesi.peter.zoltan), and don't hesitate to contact us at [L7mp](https://l7mp.io/#/contact) if you have any questions.
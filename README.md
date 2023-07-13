Custom Model Serving Runtime Demo
=================================

This repository demonstrates how to manage [Red Hat OpenShift Data Science](https://www.redhat.com/en/resources/openshift-data-science-brief) (RHODS) resources using a GitOps model with [OpenShift GitOps](https://www.redhat.com/en/technologies/cloud-computing/openshift/gitops) based on [ArgoCD](https://argo-cd.readthedocs.io/en/stable/). If you are instead interested in the more manual and UI Driven process to achieve the same thing, you should start with [this article](https://ai-on-openshift.io/odh-rhods/custom-runtime-triton/).


The Point
---------

If you are looking to deploy model inferencing into production, it's unlikely that your Data Scientists will be the ones managing the deployments of those components. They should have a defined output whereby they know a given model server will be able to use their ML model, and they should hand that over to the application teams for them to leverage and eventually the production operations team for deployment of the complete system. It's normal, in those kinds of environments, to drive deployments via a fully GitOps process. The documentation for RHODS focuses on the data scientist persona, and there may be some gaps in your knowledge for leveraging the APIs to manage your production inferencing servers and models - rather than clicking around the GUI to configure your environment, and making repeatability more challenging.

Prerequisites
-------------

- `oc`, `make`, and `jq` in your `$PATH`
- A _fresh_ OpenShift cluster. Deconflicting the things that are deployed here for a real cluster should be done carefully, and this demo is designed to inspire - not to drive production.
  - You can have RHODS already deployed, for simplicity's sake.
  - Make sure that your cluster has enough available resources to support all of the deployments here. Two m5.xlarge work instances in AWS is not enough, as an example. I tested using a cluster with three m5.4xlarge instances, but that's overkill - I think two or three m5.2xlarge instances would work fine.
  - Note the RHODS requirements [here](https://access.redhat.com/documentation/en-us/red_hat_openshift_data_science_self-managed/1.27/html/installing_openshift_data_science_self-managed_in_a_disconnected_environment/requirements-for-openshift-data-science-self-managed_install), but also add to that that your OpenShift integrated registry must be functional - which it is not in Bare Metal, VMWare, or `platform: None` UPI deployments. [The documentation](https://docs.openshift.com/container-platform/4.13/registry/configuring-registry-operator.html#image-registry-on-bare-metal-vsphere) can help you get that set up, if needed.
- Either a valid `creds.env` file with `CLUSTER`, `USER`, and `PASSWORD` defined or a valid KubeConfig file at a known path.
  - To make `creds.env`, you could run something like the following (substituting the values appropriately):
  ```shell
  cat << EOF > creds.env
  CLUSTER=https://<YOUR_CLUSTER_API_ENDPOINT>:6443
  USER=<YOUR_USER_NAME>
  PASSWORD=<YOUR_PASSWORD>
  EOF
  ```

Usage
-----

Clone this project (for example, into the terminal of your Jupyter Notebook)

```shell
git clone https://github.com/rh-aiservices-bu/custom-serving-runtime-gitops-example.git
```

and get yourself into the right directory:

```
cd ~/custom-serving-runtime-gitops-example
```

generate the `creds.env` file:

```shell
cat << EOF > creds.env
CLUSTER=https://<YOUR_CLUSTER_API_ENDPOINT>:6443
USER=<YOUR_USER_NAME>
PASSWORD=<YOUR_PASSWORD>
EOF
```

If you're deploying to a cluster that already has RHODS installed (but not OpenShift GitOps, a Data Science Project named **serving-demo-gitops**, or a MinIO deployment in that namespace), you can run:

```shell
## if you a creds file:
make already-have-rhods
## if you a kubeconfig file:
#make already-have-rhods KUBECONFIG=/path/to/your/kubeconfig
```

If you want the process to also install RHODS for you, you can instead run:

```shell
## if you a creds file:
make
## if you a kubeconfig file:
#make KUBECONFIG=/path/to/your/kubeconfig
```

Wait just a few moments for the terminal to return, and you should be able to log in to the ArgoCD instance to watch the rollout of RHODS, an S3 endpoint, and the model server and model. To help you look up that endpoint, you can run:

```shell
make credentials # KUBECONFIG=/path/to/your/kubeconfig
```

> **Note**:
>
> That command won't return an endpoint URL if a service isn't installed yet, but it should list the URLs for GitOps and RHODS once they're finished deploying.

Exploring What Happened
-----------------------

We deployed [Upstream MinIO](https://github.com/minio/minio) in its own namespace to serve some simple S3 storage, so we can use a Data Connection in RHODS without requiring a full [OpenShift Data Foundation](https://access.redhat.com/documentation/en-us/red_hat_openshift_data_foundation) deployment (which you should definitely consider in production for its HA, DR, and flexible File/Block/Object storage capabilities). It's just easier for a demo, and gets us to the same S3 API no matter what the backing store is.

We deployed RHODS itself, using the APIs for interacting with the OpenShift Operator Lifecycle Manager in the same way that the OperatorHub UI allows you to.

A Data Science Project (DSP) is a RHODS abstraction that sits on top of the traditional OpenShift Project or Kubernetes Namespace. This extra layer of metadata uses traditional OpenShift constructs for isolation and RBAC, but allows the Data Science context to bubble up into the RHODS dashboard. Here, we deployed a DSP named "Serving Demo" in the OpenShift Project "serving-demo-gitops." into the Serving Demo DSP, a Data Connection via a Kubernetes Secret, for our MinIO connection. This surfaces automatically in the RHODS dashboard appropriately. We also deployed a one-time Job to copy a model that we've already trained (a simple credit card fraud detection model) into our object store, using our Data Connection.

From there, a Serving Runtime for ModelMesh was defined. This isn't strictly required for the rest of the demo, as this mostly affects the options we have in the Dashboard for selecting the runtime for a new model server deployment. It does allow us to ensure that our model server surfaces in the dashboard, though, so it's worth doing if you're interacting with the RHODS dashboard at all. These definitions happen via an OpenShift Template object in the `redhat-ods-applications` Namespace. The template has some basic metadata for bubbling into the RHODS console, equivalent to the form-fields that are fillable in the Dashboard UI as [described in the documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_data_science/1/html/working_on_data_science_projects/model-serving-on-openshift-data-science_model-serving#adding-a-custom-model-serving-runtime_model-serving).

Afterwards, into our Data Science Project, we deployed an instance of the model server (here, copying the manifest - it would be more ideal if it were templated) as a ServingRuntime in the Kserve API, and an InferenceService to load the model we saved into MinIO into our model server.

Validating Customizations
-------------------------

At the end of the deployment, by applying a simple OpenShift GitOps Application defintion, we have a fully functional inference endpoint ready for queries. We exposed it only through an internal Service in our cluster, so it's not available publicly. Let's use a port-forward to ensure that it's working as expected:

```shell
oc port-forward -n serving-demo-gitops svc/modelmesh-serving 8008:8008 >/dev/null 2>&1 &
port_fwd=$!
sleep 1
svc=http://localhost:8008/v2/models/fraud/infer
data='{
  "inputs": [
    {
      "name": "dense_input",
      "shape": [1, 7],
      "datatype": "FP32",
      "data": [
        57.87785658389723,
        0.3111400080477545,
        1.9459399775518593,
        1.0,
        1.0,
        0.0,
        0.0
      ]
    }
  ]
}'
curl -X POST -s "$svc" -d "$data" | jq .
kill $port_fwd
```

You should see output similar to the following, if the model server is responding with a prediction on your data:

```
[1] 1229098
{
  "model_name": "fraud__isvc-b852724c43",
  "model_version": "1",
  "outputs": [
    {
      "name": "dense_3",
      "datatype": "FP32",
      "shape": [
        1,
        1
      ],
      "data": [
        0.86280495
      ]
    }
  ]
}
[1]+  Terminated              oc port-forward -n serving-demo-gitops svc/modelmesh-serving 8008:8008 > /dev/null 2>&1
```

Closing
-------

Do not use this repository to deploy custom runtimes and model servers in your environment. Explore the manifests and understand how the APIs behind RHODS come together to meet your needs and expectations, and take the elements from it that are necessary to accomplish those within your existing platform. You have deep customization at your fingertips, thanks to the interoperable standards behind the open source communities powering RHODS. If you have questions about how to make RHODS fit your expectations, please talk to your sales team.

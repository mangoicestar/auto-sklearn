# Functions performing various input/output operations for the ChaLearn AutoML challenge

# Main contributor: Arthur Pesah, August 2014
# Edits: Isabelle Guyon, October 2014

# ALL INFORMATION, SOFTWARE, DOCUMENTATION, AND DATA ARE PROVIDED "AS-IS". 
# ISABELLE GUYON, CHALEARN, AND/OR OTHER ORGANIZERS OR CODE AUTHORS DISCLAIM
# ANY EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR ANY PARTICULAR PURPOSE, AND THE
# WARRANTY OF NON-INFRIGEMENT OF ANY THIRD PARTY'S INTELLECTUAL PROPERTY RIGHTS. 
# IN NO EVENT SHALL ISABELLE GUYON AND/OR OTHER ORGANIZERS BE LIABLE FOR ANY SPECIAL, 
# INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER ARISING OUT OF OR IN
# CONNECTION WITH THE USE OR PERFORMANCE OF SOFTWARE, DOCUMENTS, MATERIALS, 
# PUBLICATIONS, OR INFORMATION MADE AVAILABLE FOR THE CHALLENGE. 

import numpy as np
import scipy
import os
try:
    import cPickle as pickle
except:
    import pickle

import helper_functions
import time


from AutoSklearn.implementations.OneHotEncoder import OneHotEncoder

#import input_routines


class DataManager:
    ''' This class aims at loading and saving data easily with a cache and at generating a dictionary (self.info) in which each key is a feature (e.g. : name, format, feat_num,...).
    Methods defined here are :
    __init__ (...)
        x.__init__([(feature, value)]) -> void        
        Initialize the info dictionary with the tuples (feature, value) given as argument. It recognizes the type of value (int, string) and assign value to info[feature]. An unlimited number of tuple can be sent.
    
    getInfo (...)
        x.getInfo (filename) -> void        
        Fill the dictionary with an info file. Each line of the info file must have this format 'feature' : value
        The information is obtained from the public.info file if it exists, or inferred from the data files        

    getInfoFromFile (...)
        x.getInfoFromFile (filename) -> void        
        Fill the dictionary with an info file. Each line of the info file must have this format 'feature' : value
        
    getFormatData (...)
        x.getFormatData (filename) -> str        
        Get the format of the file ('dense', 'sparse' or 'sparse_binary') either using the 'is_sparse' feature if it exists (for example after a call of getInfoFromFile function) and then determing if it's binary or not, or determining it alone.
        
    getNbrFeatures (...)
        x.getNbrFeatures (*filenames) -> int        
        Get the number of features, using the data files given. It first checks the format of the data. If it's a matrix, the number of features is trivial. If it's a sparse file, it gets the max feature index given in every files.
        
    getTypeProblem (...)
        x.getTypeProblem (filename) -> str        
        Get the kind of problem ('binary.classification', 'multiclass.classification', 'multilabel.classification', 'regression'), using the solution file given.
    '''
    
    def __init__(self, basename, input_dir, verbose=False, use_pickle=False):
        '''Constructor'''
        self.use_pickle = use_pickle # Turn this to true to save data as pickle (inefficient)
        self.basename = basename
        if basename in input_dir:
            self.input_dir = input_dir 
        else:
            self.input_dir = input_dir + "/" + basename + "/"   
        if self.use_pickle:
            if os.path.exists("tmp"):
                self.tmp_dir = "tmp"
            elif os.path.exists("../tmp"):
                self.tmp_dir = "../tmp" 
            else:
                os.makedirs("tmp")
                self.tmp_dir = "tmp"

        info_file = os.path.join(self.input_dir, basename + '_public.info')
        self.getInfo(info_file)
        
        print self.info
        
        self.feat_type = self.loadType(os.path.join(self.input_dir, basename + '_feat.type'), verbose=verbose)
        self.data = {}

        Xtr = self.loadData(os.path.join(self.input_dir, basename + '_train.data'), self.info['train_num'], verbose=verbose)
        print "done loading trainings data"
        
        Xva = self.loadData(os.path.join(self.input_dir, basename + '_valid.data'), self.info['valid_num'], verbose=verbose)
        print "done loading validation data"
        Xte = self.loadData(os.path.join(self.input_dir, basename + '_test.data' ), self.info['test_num' ], verbose=verbose)
        print "done loading test data"
        
        Ytr = self.loadLabel(os.path.join(self.input_dir, basename + '_train.solution'), self.info['train_num'], verbose=verbose)
        print "done loading test data"
		
        self.data['X_train'] = Xtr
        self.data['Y_train'] = Ytr
        self.data['X_valid'] = Xva
        self.data['X_test'] = Xte
        
        
        self.perform1HotEncoding()
          
    def __repr__(self):
        return "DataManager : " + self.basename

    def __str__(self):
        val = "DataManager : " + self.basename + "\ninfo:\n"
        for item in self.info:
            val = val + "\t" + item + " = " + str(self.info[item]) + "\n"
        val = val + "data:\n"

        for subset in ['X_train', 'Y_train', 'X_valid', 'X_test']:
            val = val + "\t%s = %s" % (subset, type(self.data[subset])) \
                  + str(self.data[subset].shape) + "\n"
            if isinstance(self.data[subset], scipy.sparse.spmatrix):
                val = val + "\tdensity: %f\n" % \
                            (float(len(self.data[subset].data)) /
                             self.data[subset].shape[0] /
                             self.data[subset].shape[1])
        val = val + "feat_type:\tarray" + str(self.feat_type.shape) + "\n"
        return val
                
    def loadData (self, filename, num_points, verbose=True):
        ''' Get the data from a text file in one of 3 formats: matrix, sparse, binary_sparse'''
        if verbose:  print("========= Reading " + filename)
        start = time.time()

        if self.use_pickle and os.path.exists (os.path.join (self.tmp_dir, os.path.basename(filename) + ".pickle")):
            with open (os.path.join (self.tmp_dir, os.path.basename(filename) + ".pickle"), "r") as pickle_file:
                vprint (verbose, "Loading pickle file : " + os.path.join(self.tmp_dir, os.path.basename(filename) + ".pickle"))
                return pickle.load(pickle_file)

        if 'format' not in self.info:
            self.getFormatData(filename)
        if 'feat_num' not in self.info:
            self.getNbrFeatures(filename)

        data_func = {'dense': helper_functions.read_dense_file,
                     'sparse': helper_functions.read_sparse_file,
                     'sparse_binary': helper_functions.read_sparse_binary_file}
        
        data = data_func[self.info['format']](filename, num_points, self.info['feat_num'])

        if self.use_pickle:
            with open (os.path.join (self.tmp_dir, os.path.basename(filename) + ".pickle"), "wb") as pickle_file:
                vprint (verbose, "Saving pickle file : " + os.path.join (self.tmp_dir, os.path.basename(filename) + ".pickle"))
                p = pickle.Pickler(pickle_file) 
                p.fast = True 
                p.dump(data)
        end = time.time()
        if verbose:  print( "[+] Success in %5.2f sec" % (end - start))
        return data


    def loadLabel (self, filename, num_points, verbose=True):
        ''' Get the solution/truth values'''
        if verbose:  print("========= Reading " + filename)
        start = time.time()
        if self.use_pickle and os.path.exists (os.path.join (self.tmp_dir, os.path.basename(filename) + ".pickle")):
            with open (os.path.join (self.tmp_dir, os.path.basename(filename) + ".pickle"), "r") as pickle_file:
                vprint (verbose, "Loading pickle file : " + os.path.join (self.tmp_dir, os.path.basename(filename) + ".pickle"))
                return pickle.load(pickle_file)
        if 'task' not in self.info.keys():
            self.getTypeProblem(filename)
    
        # IG: Here change to accommodate the new multiclass label format
        if self.info['task'] == 'multilabel.classification':
			#cast into ints
            label = (helper_functions.read_dense_file_unknown_width(filename, num_points)).astype(np.int)
        elif self.info['task'] == 'multiclass.classification':
            label = helper_functions.read_dense_file_unknown_width(filename, num_points)
            # read the class from the only non zero entry in each line!
            # should be ints right away
            label = np.where(label!=0)[1];
        else:
            label = helper_functions.read_dense_file_unknown_width(filename, num_points)
   
        if self.use_pickle:
            with open (os.path.join (self.tmp_dir, os.path.basename(filename) + ".pickle"), "wb") as pickle_file:
                vprint (verbose, "Saving pickle file : " + os.path.join (self.tmp_dir, os.path.basename(filename) + ".pickle"))
                p = pickle.Pickler(pickle_file) 
                p.fast = True 
                p.dump(label)

        end = time.time()
        if verbose:  print( "[+] Success in %5.2f sec" % (end - start))
        return label

    
    def perform1HotEncoding(self):
        if not hasattr(self, "data"):
            raise ValueError("perform1HotEncoding can only be called when "
                             "data is loaded")
        if hasattr(self, "encoder"):
            raise ValueError("perform1HotEncoding can only be called on "
                             "non-encoded data.")

        sparse = True if self.info['is_sparse'] == 1 else False
        has_missing = True if self.info['has_missing'] else False

        to_encode = ['Categorical']
        if has_missing:
            to_encode += ['Binary']
        encoding_mask = [feat_type in to_encode for feat_type in self.feat_type]

        categorical = [True if feat_type.lower() == 'categorical' else False
                       for feat_type in self.feat_type]
        predicted_RAM_usage = float(helper_functions.predict_RAM_usage(
            self.data['X_train'], categorical)) / 1024 / 1024

        if predicted_RAM_usage > 1000:
            sparse = True

        if any(encoding_mask):
            encoder = OneHotEncoder(categorical_features=encoding_mask,
                                    dtype=np.float64, sparse=False)
            self.data['X_train'] = encoder.fit_transform(self.data['X_train'])
            if 'X_valid' in self.data:
                self.data['X_valid'] = encoder.transform(self.data['X_valid'])
            if 'X_test' in self.data:
                self.data['X_test'] = encoder.transform(self.data['X_test'])

            if not sparse and predicted_RAM_usage > 1000:
                self.data['X_train'] = self.data['X_train'].todense()
                if 'X_valid' in self.data:
                    self.data['X_valid'] = self.data['X_valid'].todense()
                if 'X_test' in self.data:
                    self.data['X_test'] = self.data['X_test'].todense()

            self.encoder = encoder

    def loadType (self, filename, verbose=True):
        ''' Get the variable types'''
        if verbose:  print("========= Reading " + filename)
        start = time.time()
        type_list = []
        if os.path.isfile(filename):
            type_list = helper_functions.file_to_array (filename, verbose=False)
        else:
            n=self.info['feat_num']
            type_list = [self.info['feat_type']]*n
        type_list = np.array(type_list).ravel()
        end = time.time()
        if verbose:  print( "[+] Success in %5.2f sec" % (end - start))
        return type_list


    def getInfo (self, filename, verbose=True):
        ''' Get all information {attribute = value} pairs from the filename (public.info file), 
              if it exists, otherwise, output default values''' 
        self.info = {}
        if filename==None:
            basename = self.basename
            input_dir = self.input_dir
        else:   
            basename = os.path.basename(filename).split('_')[0]
            input_dir = os.path.dirname(filename)
        if os.path.exists(filename):
            self.getInfoFromFile (filename)
            vprint (verbose, "Info file found : " + os.path.abspath(filename))
            # Finds the data format ('dense', 'sparse', or 'sparse_binary')   
            self.getFormatData(os.path.join(input_dir, basename + '_train.data'))
        '''
        else:    
            vprint (verbose, "Info file NOT found : " + os.path.abspath(filename))            
            # Hopefully this never happens because this is done in a very inefficient way
            # reading the data multiple times...              
            self.info['usage'] = 'No Info File'
            self.info['name'] = basename
            # Get the data format and sparsity
            self.getFormatData(os.path.join(input_dir, basename + '_train.data'))
            # Assume no categorical variable and no missing value (we'll deal with that later)
            self.info['has_categorical'] = 0
            self.info['has_missing'] = 0              
            # Get the target number, label number, target type and task               
            self.getTypeProblem(os.path.join(input_dir, basename + '_train.solution'))
            if self.info['task']=='regression':
                self.info['metric'] = 'r2_metric'
            else:
                self.info['metric'] = 'auc_metric'
            # Feature type: Numerical, Categorical, or Binary
            # Can also be determined from [filename].type        
            self.info['feat_type'] = 'Mixed'  
            # Get the number of features and patterns
            self.getNbrFeatures(os.path.join(input_dir, basename + '_train.data'), os.path.join(input_dir, basename + '_test.data'), os.path.join(input_dir, basename + '_valid.data'))
            self.getNbrPatterns(basename, input_dir, 'train')
            self.getNbrPatterns(basename, input_dir, 'valid')
            self.getNbrPatterns(basename, input_dir, 'test')
            # Set default time budget
            self.info['time_budget'] = 600
        '''
        return self.info



    def getInfoFromFile (self, filename):
        ''' Get all information {attribute = value} pairs from the public.info file'''
        with open (filename, "r") as info_file:
            lines = info_file.readlines()
            features_list = list(map(lambda x: tuple(x.strip("\'").split(" = ")), lines))
            
            for (key, value) in features_list:
                self.info[key] = value.rstrip().strip("'").strip(' ')
                if self.info[key].isdigit(): # if we have a number, we want it to be an integer
                    self.info[key] = int(self.info[key])
        return self.info     




    def getFormatData(self,filename):
        ''' Get the data format directly from the data file (in case we do not have an info file)'''
        if 'format' in self.info.keys():
            return self.info['format']
        if 'is_sparse' in self.info.keys():
            if self.info['is_sparse'] == 0:
                self.info['format'] = 'dense'
            else:
                data = helper_functions.read_first_line (filename)
                if ':' in data[0]:
                    self.info['format'] = 'sparse'
                else:
                    self.info['format'] = 'sparse_binary'
        else:
            data = helper_functions.file_to_array (filename)
            if ':' in data[0][0]:
                self.info['is_sparse'] = 1
                self.info['format'] = 'sparse'
            else:
                nbr_columns = len(data[0])
                for row in range (len(data)):
                    if len(data[row]) != nbr_columns:
                        self.info['format'] = 'sparse_binary'
                if 'format' not in self.info.keys():
                    self.info['format'] = 'dense'
                    self.info['is_sparse'] = 0            
        return self.info['format']
    """
    def getNbrFeatures (self, *filenames):
        ''' Get the number of features directly from the data file (in case we do not have an info file)'''
        if 'feat_num' not in self.info.keys():
            self.getFormatData(filenames[0])
            if self.info['format'] == 'dense':
                data = data_converter.file_to_array(filenames[0])
                self.info['feat_num'] = len(data[0])
            elif self.info['format'] == 'sparse':
                self.info['feat_num'] = 0
                for filename in filenames:
                    sparse_list = data_converter.sparse_file_to_sparse_list (filename)
                    last_column = [sparse_list[i][-1] for i in range(len(sparse_list))]
                    last_column_feature = [a for (a,b) in last_column]
                    self.info['feat_num'] = max(self.info['feat_num'], max(last_column_feature))                
            elif self.info['format'] == 'sparse_binary':
                self.info['feat_num'] = 0
                for filename in filenames:
                    data = data_converter.file_to_array (filename)
                    last_column = [int(data[i][-1]) for i in range(len(data))]
                    self.info['feat_num'] = max(self.info['feat_num'], max(last_column))            
        return self.info['feat_num']
  
    def getNbrPatterns (self, basename, info_dir, datatype):
        ''' Get the number of patterns directly from the data file (in case we do not have an info file)'''
        line_num = data_converter.num_lines(os.path.join(info_dir, basename + '_' + datatype + '.data'))
        self.info[datatype+'_num'] =  line_num
        return line_num
        
    def getTypeProblem (self, solution_filename):
        ''' Get the type of problem directly from the solution file (in case we do not have an info file)'''
        if 'task' not in self.info.keys():
            solution = np.array(data_converter.file_to_array(solution_filename))
            target_num = solution.shape[1]
            self.info['target_num']=target_num
            if target_num == 1: # if we have only one column
                solution = np.ravel(solution) # flatten
                nbr_unique_values = len(np.unique(solution))
                if nbr_unique_values < len(solution)/8:
                    # Classification
                    self.info['label_num'] = nbr_unique_values
                    if nbr_unique_values == 2:
                        self.info['task'] = 'binary.classification'
                        self.info['target_type'] = 'Binary'
                    else:
                        self.info['task'] = 'multiclass.classification'
                        self.info['target_type'] = 'Categorical'
                else:
                    # Regression
                    self.info['label_num'] = 0
                    self.info['task'] = 'regression'
                    self.info['target_type'] = 'Numerical'     
            else:
                # Multilabel or multiclass       
                self.info['label_num'] = target_num
                self.info['target_type'] = 'Binary' 
                if any(item > 1 for item in map(np.sum,solution.astype(int))):
                    self.info['task'] = 'multilabel.classification'     
                else:
                    self.info['task'] = 'multiclass.classification'        
        return self.info['task']
        
    """


def vprint(mode, t):
    ''' Print to stdout, only if in verbose mode'''
    if(mode):
            print(t) 

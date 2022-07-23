//
//  main.c
//  NMLIVM
//
//  Created by nomadli on 2022/7/21.
//

#import <sys/stat.h>
#import "NMLIVM.h"

//extern char* const *environ;      //this is a env
//gethostname(char*, len);          //get host name
//getlogin_r(char*, len);           //get cur usr
//getcwd(char*, len);               //get cur dir
//signal(SIGINT, SIG_IGN);          //ctrl + c
//signal(SIGQUIT, SIG_IGN);         //ctrl + /
//signal(SIGTSTP, SIG_IGN);         //ctrl + z

void open_vm(char *who, char *tips) {
}

void create_linux_vm(char *who, char *tips) {
}

__attribute__((__unused__)) static char* vm_filename_completion(const char *text, int state)
{
    char *ret = filename_completion_function(text, state);
    if (ret == NULL) {
        return NULL;
    }
    
    static char path[512];
    nmli_absolute_path(ret, path);
    
    struct stat st;
    if (stat(path, &st) != 0) {
        return ret;
    }
    
    if (!(st.st_mode & S_IFDIR)) {
        return ret;
    }
    
    size_t len = strlen(ret);
    if (ret[len - 1] == '/') {
        return ret;
    }
        
    char *nret = malloc(len + 2);
    memcpy(nret, ret, len);
    nret[len++] = '/';
    nret[len] = '\0';
    free(ret);
    return nret;
}

int main(int argc, const char * argv[]) {
    if (argc >= 2 && argv[1][0] != '\0') {
        run_vm(argc, argv);
        exit(0);
    }
    
    rl_initialize();
    rl_completion_entry_function = (Function*)vm_filename_completion;
    rl_completion_append_character = 0;
    
    NMLIVM vm;
    memset(&vm, 0, sizeof(vm));
    if (getlogin_r(vm.who, sizeof(vm.who)) != 0) {
        NMLI_LOG_VAR("get whois err:%d %s\n", errno, strerror(errno));
        return -1;
    }
    vm.self_path = argv[0];
    
    start_menu(&vm);
    return 0;
}
